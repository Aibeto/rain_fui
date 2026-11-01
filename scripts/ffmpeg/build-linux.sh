#!/usr/bin/env bash
# =============================================================================
# build-linux.sh — native Linux x86_64 FFmpeg build (contract target linux-x64).
#
#   scripts/ffmpeg/build-linux.sh [--jobs N] [--clean] [--arch x86_64]
#
# Artifacts (contract §5): build/ffmpeg/dist/linux-x64/ffmpeg + version.txt
# Build tree:              build/ffmpeg/ffbuild/linux-x64/
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET="linux-x64"
ARCH="x86_64"
CLEAN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--jobs N] [--clean] [--arch x86_64]

Build the native Linux x86_64 'ffmpeg' executable (contract target: $TARGET).
Requires a host C toolchain; LTO is enabled by default (contract §3).

Options:
      --jobs N      parallel compile jobs (default: $(ffmpeg_default_jobs))
      --clean       delete build/ffmpeg/ffbuild/$TARGET first
EOF
    ffmpeg_usage_common
    cat <<EOF
Environment:
      CC                 C compiler (default: gcc; clang is auto-detected for LTO policy)
      FFMPEG_LTO=0       disable LTO (debug only; CI keeps LTO on)
      FFMPEG_WITH_FFPROBE=1  also build ffprobe
      FFMPEG_EXTERNAL_LIBS=1 link libopus/libvorbis/libvpx/libx264/libx265/
                           libaom/libsvtav1/libmp3lame plus vaapi and qsv
      JOBS               same as --jobs
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --jobs)      JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)    JOBS="${1#*=}"; shift ;;
        --clean)     CLEAN=1; shift ;;
        --arch)      ARCH="${2:?--arch needs a value}"; shift 2 ;;
        --arch=*)    ARCH="${1#*=}"; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "unknown argument '$1' (see --help)" ;;
    esac
done

ffmpeg_validate_jobs
require_ffmpeg_src
[ "$ARCH" = "x86_64" ] || die "build-linux.sh only supports --arch x86_64 (contract §5 target linux-x64)"

CC="${CC:-gcc}"
require_cmd "${CC%% *}" "install a C toolchain (gcc/clang) or set CC="
KIND="$(ffmpeg_compiler_kind "$CC")"

builddir="$(ffmpeg_builddir "$TARGET")"
distdir="$(ffmpeg_distdir "$TARGET")"
ffmpeg_check_target_name "$TARGET"
mkdir -p "$distdir"

ffmpeg_banner "$TARGET"
log "compiler: $CC ($KIND)"

if [ "$CLEAN" = "1" ]; then
    ffmpeg_reset_builddir "$builddir"
fi

args=( "${FFMPEG_BASE_FLAGS[@]}" )
args+=( --prefix="$builddir/prefix" --cc="$CC" )

lto_cfg="$(ffmpeg_lto_configure_flags "$KIND")"
if [ -n "$lto_cfg" ]; then
    args+=( "$lto_cfg" )
fi

ldflags="$(ffmpeg_lto_link_flags "$KIND")"
if [ -n "$ldflags" ]; then
    args+=( --extra-ldflags="$ldflags" )
fi

if ffmpeg_zlib_available "$CC"; then
    args+=( --enable-zlib )
    log "zlib: enabled (host sysroot provides zlib.h)"
else
    log "zlib: not available, skipping --enable-zlib (contract §4)"
fi

if [ "${FFMPEG_EXTERNAL_LIBS:-0}" = "1" ]; then
    export PKG_CONFIG_PATH
    PKG_CONFIG_PATH="$(ffmpeg_deps_pkg_config_path "$(ffmpeg_deps_prefix)")"
    extra_cflags="$(ffmpeg_external_extra_cflags)"
    extra_ldflags="$(ffmpeg_external_extra_ldflags)"
    [ -n "$extra_cflags" ] && args+=( --extra-cflags="$extra_cflags" )
    [ -n "$extra_ldflags" ] && args+=( --extra-ldflags="$extra_ldflags" )
    while IFS= read -r flag; do
        [ -n "$flag" ] && args+=( "$flag" )
    done < <(ffmpeg_external_flags linux)
    while IFS= read -r flag; do
        [ -n "$flag" ] && args+=( "$flag" )
    done < <(ffmpeg_external_pkg_config_flags)
    log "external libraries: enabled (prefix $(ffmpeg_deps_prefix))"
fi

if ffmpeg_has_x86asm; then
    log "x86 asm: enabled ($(command -v nasm || command -v yasm))"
else
    warn "nasm/yasm not found — building with --disable-x86asm (slower SIMD, see docs/ffmpeg-build.md)"
    args+=( --disable-x86asm )
fi

while IFS= read -r flag; do
    [ -n "$flag" ] && args+=( "$flag" )
done < <(ffmpeg_program_flags)

start="$(date +%s)"
ffmpeg_configure "$builddir" "${args[@]}"
ffmpeg_assert_license "$builddir"
ffmpeg_make "$builddir"

[ -f "$builddir/ffmpeg" ] || die "make finished but '$builddir/ffmpeg' is missing"

ffmpeg_copy_artifact "$builddir/ffmpeg" "$distdir/ffmpeg" 0755
first="$(ffmpeg_version_file "$distdir/ffmpeg" "$distdir/version.txt")"
ffmpeg_require_version_line "$distdir/ffmpeg" "$(ffmpeg_tag)"
ffmpeg_report_artifact "$distdir/ffmpeg"

printf '\n[ffmpeg] %s: artifact -version first line:\n  %s\n' "$TARGET" "$first"
log "$TARGET build complete in $(ffmpeg_elapsed "$start")"
log "dist: $distdir"
