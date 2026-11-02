#!/usr/bin/env bash
# =============================================================================
# build-macos.sh — universal macOS 'ffmpeg' (contract target macos).
#
#   scripts/ffmpeg/build-macos.sh [--jobs N] [--clean] [--arch "arm64 x86_64"]
#
# Each architecture is configured and compiled in its own build tree, then the
# two binaries are joined with lipo. Artifacts (contract §5):
#
#   build/ffmpeg/dist/macos/ffmpeg        universal, ad-hoc signed
#   build/ffmpeg/dist/macos/version.txt
# Build trees: build/ffmpeg/ffbuild/macos-arm64/, build/ffmpeg/ffbuild/macos-x64/
#
# macOS is the one platform that cannot carry an unsigned helper: on Apple
# Silicon an unsigned or wrongly signed binary does not launch at all, so the
# dist binary is ad-hoc signed here. The app build re-signs the copy it puts in
# Contents/Frameworks (see macos/ffmpeg_helper/).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET="macos"
ARCHS_DEFAULT="arm64 x86_64"
ARCHS=""
CLEAN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--jobs N] [--clean] [--arch "arm64 x86_64"]

Build the universal macOS 'ffmpeg' executable (contract target: $TARGET).
Needs Xcode (or the command line tools) and runs on macOS only.

Options:
      --jobs N      parallel compile jobs (default: $(ffmpeg_default_jobs))
      --clean       delete both architecture build trees first
      --arch LIST   space separated architectures (default: "$ARCHS_DEFAULT")

Environment:
      MACOSX_DEPLOYMENT_TARGET  minimum macOS version (default: 11.0)
      FFMPEG_LTO=0              disable LTO (debug only)
      FFMPEG_WITH_FFPROBE=1     also build ffprobe
      FFMPEG_EXTERNAL_LIBS=1    link libopus/libvorbis/libvpx/libx264/libx265/
                                libaom/libsvtav1/libmp3lame/libwebp plus the
                                VideoToolbox and AudioToolbox back ends
      JOBS                      same as --jobs
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --jobs)      JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)    JOBS="${1#*=}"; shift ;;
        --clean)     CLEAN=1; shift ;;
        --arch)      ARCHS="${2:?--arch needs a value}"; shift 2 ;;
        --arch=*)    ARCHS="${1#*=}"; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "unknown argument '$1' (see --help)" ;;
    esac
done

[ "$(uname -s)" = "Darwin" ] || die "build-macos.sh only runs on macOS (needs xcrun and the macOS SDK)"
require_cmd xcrun "install Xcode or the command line tools (xcode-select --install)"
require_ffmpeg_src
[ -n "$ARCHS" ] || ARCHS="$ARCHS_DEFAULT"
ffmpeg_validate_jobs

sdk="$(xcrun --sdk macosx --show-sdk-path)"
[ -d "$sdk" ] || die "macOS SDK not found (xcrun --sdk macosx --show-sdk-path returned '$sdk')"
macmin="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
clang="$(xcrun --sdk macosx --find clang)"

distdir="$(ffmpeg_distdir "$TARGET")"
ffmpeg_check_target_name "$TARGET"
mkdir -p "$distdir"

ffmpeg_banner "$TARGET"
log "SDK: $sdk"
log "deployment target: $macmin"
log "architectures: $ARCHS"

slices=()

for arch in $ARCHS; do
    case "$arch" in
        arm64)  deps_target="macos-arm64" ;;
        x86_64) deps_target="macos-x64" ;;
        *) die "unknown architecture '$arch' (expected arm64 or x86_64)" ;;
    esac

    buildtarget="$deps_target"
    builddir="$(ffmpeg_builddir "$buildtarget")"
    export FFMPEG_DEPS_TARGET="$deps_target"

    log "--- $arch ($buildtarget) ---"

    if [ "$CLEAN" = "1" ]; then
        ffmpeg_reset_builddir "$builddir"
    fi

    args=( "${FFMPEG_BASE_FLAGS[@]}" )
    args+=( --prefix="$builddir/prefix" )
    args+=( --cc="$clang" )
    args+=( --arch="$arch" --target-os=darwin )
    # 两个架构都在同一台机器上编，所以始终按交叉编译处理：configure 不能靠运行
    # 目标文件去猜 sizeof 之类的东西。
    args+=( --enable-cross-compile --sysroot="$sdk" )

    # configure 里 cflags/ldflags 各只留一份，先攒再传：后面外置库还要往里加 -L。
    extra_cflags="-arch $arch -isysroot $sdk -mmacosx-version-min=$macmin"
    extra_ldflags="-arch $arch -isysroot $sdk -mmacosx-version-min=$macmin"

    # Same LTO policy as Linux (contract §3): clang gets -flto=thin, and the
    # link step needs the matching flag or the archives will not resolve.
    kind="$(ffmpeg_compiler_kind "$clang")"
    lto_cfg="$(ffmpeg_lto_configure_flags "$kind")"
    if [ -n "$lto_cfg" ]; then
        args+=( "$lto_cfg" )
    fi
    lto_ld="$(ffmpeg_lto_link_flags "$kind")"
    if [ -n "$lto_ld" ]; then
        extra_ldflags="$extra_ldflags $lto_ld"
    fi

    if ffmpeg_zlib_available "$clang" -arch "$arch" -isysroot "$sdk"; then
        args+=( --enable-zlib )
        log "zlib: enabled (SDK provides zlib.h)"
    else
        log "zlib: not available, skipping --enable-zlib (contract §4)"
    fi

    if [ "${FFMPEG_EXTERNAL_LIBS:-0}" = "1" ]; then
        prefix="$(ffmpeg_deps_prefix)"
        if [ -d "$prefix/lib" ] || [ -d "$prefix/lib64" ]; then
            export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/lib64/pkgconfig"
            export PKG_CONFIG_PATH=""
            dep_cflags="$(ffmpeg_external_extra_cflags)"
            dep_ldflags="$(ffmpeg_external_extra_ldflags)"
            [ -n "$dep_cflags" ] && extra_cflags="$dep_cflags $extra_cflags"
            [ -n "$dep_ldflags" ] && extra_ldflags="$dep_ldflags $extra_ldflags"
            while IFS= read -r flag; do
                [ -n "$flag" ] && args+=( "$flag" )
            done < <(ffmpeg_external_flags macos)
            while IFS= read -r flag; do
                [ -n "$flag" ] && args+=( "$flag" )
            done < <(ffmpeg_external_pkg_config_flags)
            log "external libraries: enabled (prefix $prefix)"
        else
            warn "FFMPEG_EXTERNAL_LIBS=1 but $prefix is empty; run build-deps.sh --target $deps_target first"
        fi
    fi

    args+=( --extra-cflags="$extra_cflags" --extra-ldflags="$extra_ldflags" )

    while IFS= read -r flag; do
        [ -n "$flag" ] && args+=( "$flag" )
    done < <(ffmpeg_program_flags)

    ffmpeg_configure "$builddir" "${args[@]}"
    ffmpeg_assert_license "$builddir"
    ffmpeg_make "$builddir"

    [ -f "$builddir/ffmpeg" ] || die "make finished but '$builddir/ffmpeg' is missing"

    slice="$distdir/ffmpeg-$arch"
    ffmpeg_copy_artifact "$builddir/ffmpeg" "$slice" 0755
    slices+=( "$slice" )
done

if [ "${#slices[@]}" -eq 1 ]; then
    mv -f "${slices[0]}" "$distdir/ffmpeg"
else
    lipo -create "${slices[@]}" -output "$distdir/ffmpeg" \
        || die "lipo failed to join: ${slices[*]}"
    rm -f "${slices[@]}"
fi
chmod 0755 "$distdir/ffmpeg"

# Apple Silicon refuses to launch an unsigned binary, and the arm64 slice is in
# every universal build, so sign here as well as in the app build phase.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$distdir/ffmpeg" \
        || die "codesign failed for $distdir/ffmpeg"
    log "codesign: ad-hoc signature applied"
else
    warn "codesign not found; the arm64 slice will not launch until it is signed"
fi

first="$(ffmpeg_version_file "$distdir/ffmpeg" "$distdir/version.txt")"
ffmpeg_require_version_line "$distdir/ffmpeg" "$(ffmpeg_tag)"
ffmpeg_report_artifact "$distdir/ffmpeg"
lipo -info "$distdir/ffmpeg" 2>/dev/null | sed 's/^/[ffmpeg]   /' || true

printf '\n[ffmpeg] %s: artifact -version first line:\n  %s\n' "$TARGET" "$first"
log "$TARGET build complete"
log "dist: $distdir"
ffmpeg_remind_install macos
