#!/usr/bin/env bash
# =============================================================================
# build-android.sh — Android FFmpeg builds via the NDK clang toolchain.
#
#   scripts/ffmpeg/build-android.sh [--jobs N] [--abis a,b,c] [--api 24] [--clean]
#
# Contract targets (§5): android-arm64-v8a / android-armeabi-v7a / android-x86_64
# Artifact: build/ffmpeg/dist/<target>/libffmpeg_exe.so + version.txt
# The ELF executable is renamed to libffmpeg_exe.so so it is packaged into the
# APK as a native "library" and extracted to nativeLibraryDir (contract §8).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

ABIS="arm64-v8a,armeabi-v7a,x86_64"
API="24"
CLEAN=0
DEFAULT_NDK="$HOME/Android/Sdk/ndk/28.2.13676358"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--jobs N] [--abis arm64-v8a,armeabi-v7a,x86_64] [--api 24] [--clean]

Cross-compile FFmpeg for Android with the NDK clang toolchain.
Default ABIs: $ABIS (all three are Flutter-supported ABIs).
Default API: 24 (Flutter minSdk).

Options:
      --jobs N      parallel compile jobs (default: $(ffmpeg_default_jobs))
      --abis LIST   comma separated subset of arm64-v8a,armeabi-v7a,x86_64
      --api N       Android API level for the clang wrappers (default: $API)
      --clean       delete the per-target build directory first
EOF
    ffmpeg_usage_common
    cat <<EOF
Environment:
      ANDROID_NDK_HOME / ANDROID_NDK_ROOT   NDK root (default: $DEFAULT_NDK)
      JOBS, FFMPEG_LTO=0, FFMPEG_WITH_FFPROBE=1
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --jobs)    JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)  JOBS="${1#*=}"; shift ;;
        --abis)    ABIS="${2:?--abis needs a value}"; shift 2 ;;
        --abis=*)  ABIS="${1#*=}"; shift ;;
        --api)     API="${2:?--api needs a value}"; shift 2 ;;
        --api=*)   API="${1#*=}"; shift ;;
        --clean)   CLEAN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         die "unknown argument '$1' (see --help)" ;;
    esac
done

ffmpeg_validate_jobs
require_ffmpeg_src
case "$API" in ''|*[!0-9]*) die "--api must be a number (got '$API')" ;; esac

case "$(uname -s)" in
    Linux)  HOST_TAG="linux-x86_64" ;;
    Darwin) HOST_TAG="darwin-x86_64" ;;
    MINGW*|MSYS*|CYGWIN*) HOST_TAG="windows-x86_64" ;;
    *) die "unsupported host '$(uname -s)' for the Android NDK" ;;
esac

ffmpeg_find_ndk() {
    local cand best=""
    local -a candidates=()
    if [ -n "${ANDROID_NDK_HOME:-}" ]; then candidates+=("$ANDROID_NDK_HOME"); fi
    if [ -n "${ANDROID_NDK_ROOT:-}" ]; then candidates+=("$ANDROID_NDK_ROOT"); fi
    if [ -z "${ANDROID_NDK_HOME:-}${ANDROID_NDK_ROOT:-}" ]; then
        candidates+=("$DEFAULT_NDK")
        if [ -d "$HOME/Android/Sdk/ndk" ]; then
            while IFS= read -r cand; do candidates+=("$cand"); done \
                < <(find "$HOME/Android/Sdk/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V)
        fi
        candidates+=("/opt/android-ndk" "$HOME/Android/Sdk/ndk-bundle")
    fi
    for cand in "${candidates[@]}"; do
        if [ -d "$cand/toolchains/llvm/prebuilt/$HOST_TAG" ]; then
            best="$cand"
            break
        fi
    done
    [ -n "$best" ] || die "Android NDK not found (looked for toolchains/llvm/prebuilt/$HOST_TAG).
Install it (Android Studio SDK Manager) or set ANDROID_NDK_HOME=/path/to/ndk"
    printf '%s\n' "$best"
}

NDK="$(ffmpeg_find_ndk)"
TC="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
SYSROOT="$TC/sysroot"
log "NDK: $NDK ($(grep -m1 '^Pkg.Revision' "$NDK/source.properties" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true))"
log "API level: $API"

abi_arch() {
    case "$1" in
        arm64-v8a)   printf 'aarch64\n' ;;
        armeabi-v7a) printf 'arm\n' ;;
        x86_64)      printf 'x86_64\n' ;;
        *) die "unsupported ABI '$1' (expected arm64-v8a, armeabi-v7a or x86_64)" ;;
    esac
}
abi_cpu() {
    case "$1" in
        arm64-v8a)   printf 'armv8-a\n' ;;
        armeabi-v7a) printf 'armv7-a\n' ;;
        x86_64)      printf 'x86-64\n' ;;
    esac
}
abi_triple() {
    case "$1" in
        arm64-v8a)   printf 'aarch64-linux-android\n' ;;
        armeabi-v7a) printf 'armv7a-linux-androideabi\n' ;;
        x86_64)      printf 'x86_64-linux-android\n' ;;
    esac
}
# `file(1)` prints the ELF machine in its own spelling ("ARM aarch64", "ARM",
# "x86-64"), so compare case-insensitively against these lowercase tokens.
abi_elf_machine() {
    case "$1" in
        arm64-v8a)   printf 'aarch64\n' ;;
        armeabi-v7a) printf 'arm\n' ;;
        x86_64)      printf 'x86-64\n' ;;
    esac
}

IFS=',' read -r -a ABI_LIST <<< "$ABIS"
[ "${#ABI_LIST[@]}" -gt 0 ] || die "--abis is empty"

start_all="$(date +%s)"
for abi in "${ABI_LIST[@]}"; do
    # trim whitespace
    abi="${abi//[[:space:]]/}"
    [ -n "$abi" ] || continue

    target="android-$abi"
    FFMPEG_DEPS_TARGET="$target"
    ffmpeg_check_target_name "$target"
    arch="$(abi_arch "$abi")"
    cpu="$(abi_cpu "$abi")"
    triple="$(abi_triple "$abi")"
    machine="$(abi_elf_machine "$abi")"

    CC="$TC/bin/${triple}${API}-clang"
    CXX="$TC/bin/${triple}${API}-clang++"
    AR="$TC/bin/llvm-ar"
    RANLIB="$TC/bin/llvm-ranlib"
    NM="$TC/bin/llvm-nm"
    STRIP="$TC/bin/llvm-strip"
    [ -x "$CC" ] || die "NDK clang wrapper not found: $CC
API $API may be unsupported by this NDK — try --api 24 (Flutter minSdk) or a newer NDK."
    [ -x "$CXX" ] || die "NDK clang++ wrapper not found: $CXX"

    builddir="$(ffmpeg_builddir "$target")"
    distdir="$(ffmpeg_distdir "$target")"
    mkdir -p "$distdir"

    ffmpeg_banner "$target"
    log "abi=$abi arch=$arch cpu=$cpu cc=$CC"

    if [ "$CLEAN" = "1" ]; then
        ffmpeg_reset_builddir "$builddir"
    fi

    args=( "${FFMPEG_BASE_FLAGS[@]}" )
    args+=(
        --prefix="$builddir/prefix"
        --target-os=android
        --arch="$arch"
        --cpu="$cpu"
        --enable-cross-compile
        --cc="$CC"
        --cxx="$CXX"
        --ar="$AR"
        --ranlib="$RANLIB"
        --nm="$NM"
        --strip="$STRIP"
        --sysroot="$SYSROOT"
        # 16 KB page size compliance (contract §5 / Android 15+ devices).
        --extra-ldflags="-Wl,-z,max-page-size=16384"
    )

    lto_cfg="$(ffmpeg_lto_configure_flags clang)"
    if [ -n "$lto_cfg" ]; then
        args+=( "$lto_cfg" )
    fi

    if ffmpeg_zlib_available "$CC" "--sysroot=$SYSROOT"; then
        args+=( --enable-zlib )
        log "zlib: enabled (NDK sysroot provides zlib.h)"
    else
        log "zlib: not available, skipping --enable-zlib"
    fi

    if [ "${FFMPEG_EXTERNAL_LIBS:-0}" = "1" ]; then
        export PKG_CONFIG_PATH PKG_CONFIG_LIBDIR
        PKG_CONFIG_PATH="$(ffmpeg_deps_pkg_config_path "$(ffmpeg_deps_prefix)")"
        # PKG_CONFIG_PATH only prepends to the default search path, so a host
        # libogg would still win; LIBDIR replaces the defaults entirely.
        PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
        extra_cflags="$(ffmpeg_external_extra_cflags)"
        extra_ldflags="$(ffmpeg_external_extra_ldflags)"
        [ -n "$extra_cflags" ] && args+=( --extra-cflags="$extra_cflags" )
        [ -n "$extra_ldflags" ] && args+=( --extra-ldflags="$extra_ldflags" )
        while IFS= read -r flag; do
            [ -n "$flag" ] && args+=( "$flag" )
        done < <(ffmpeg_external_flags android)
    while IFS= read -r flag; do
        [ -n "$flag" ] && args+=( "$flag" )
    done < <(ffmpeg_external_pkg_config_flags)
        log "external libraries: android set from $(ffmpeg_deps_prefix)"
    fi

    if [ "$arch" = "x86_64" ] && ! ffmpeg_has_x86asm; then
        warn "nasm/yasm not found — disabling x86 asm for $target (slower, valid output)"
        args+=( --disable-x86asm )
    fi

    while IFS= read -r flag; do
        [ -n "$flag" ] && args+=( "$flag" )
    done < <(ffmpeg_program_flags)

    t0="$(date +%s)"
    ffmpeg_configure "$builddir" "${args[@]}"
    ffmpeg_assert_license "$builddir"
    ffmpeg_make "$builddir"

    src="$builddir/ffmpeg"
    [ -f "$src" ] || die "make finished but '$src' is missing for $target"

    dst="$distdir/libffmpeg_exe.so"
    ffmpeg_copy_artifact "$src" "$dst" 0755

    if command -v file >/dev/null 2>&1; then
        ftype="$(file -b "$dst")"
        case "$ftype" in
            *ELF*) ;;
            *) die "$dst is not an ELF executable: $ftype" ;;
        esac
        ftype_lc="$(printf '%s' "$ftype" | tr '[:upper:]' '[:lower:]')"
        case "$ftype_lc" in
            *"$machine"*) log "file: $ftype" ;;
            *) die "$dst has wrong ELF machine (expected $machine): $ftype" ;;
        esac
    fi

    ffmpeg_version_file "" "$distdir/version.txt" \
        "ffmpeg version $(ffmpeg_tag) (cross-compiled for $target)" >/dev/null
    ffmpeg_report_artifact "$dst"
    log "$target done in $(ffmpeg_elapsed "$t0")"
done

log "android build complete in $(ffmpeg_elapsed "$start_all")"
ffmpeg_remind_install android
log "dist: $FFMPEG_DIST/{$(printf 'android-%s,' "${ABI_LIST[@]}" | sed 's/,$//')}"
