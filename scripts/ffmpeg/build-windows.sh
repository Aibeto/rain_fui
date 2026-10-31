#!/usr/bin/env bash
# =============================================================================
# build-windows.sh — Windows x86_64 FFmpeg build (contract target windows-x64).
#
#   scripts/ffmpeg/build-windows.sh [--jobs N] [--clean] [--arch x86_64]
#
# Two supported hosts, auto-detected:
#   * MSYS2 / Git-Bash on Windows  -> native mingw-w64 gcc build
#   * Linux with mingw-w64 cross gcc -> cross build (x86_64-w64-mingw32-*)
#
# Artifacts (contract §5): build/ffmpeg/dist/windows-x64/ffmpeg.exe + version.txt
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET="windows-x64"
ARCH="x86_64"
CLEAN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--jobs N] [--clean] [--arch x86_64]

Build the Windows x86_64 'ffmpeg.exe' (contract target: $TARGET).
Runs natively under MSYS2/Git-Bash, or cross-compiles from Linux with mingw-w64.

Options:
      --jobs N      parallel compile jobs (default: $(ffmpeg_default_jobs))
      --clean       delete build/ffmpeg/ffbuild/$TARGET first
EOF
    ffmpeg_usage_common
    cat <<EOF
Environment:
      CC                 mingw gcc (native default: gcc; cross default: x86_64-w64-mingw32-gcc)
      CROSS_PREFIX       override the cross prefix (default: x86_64-w64-mingw32-)
      FFMPEG_LTO=0       disable LTO (debug only)
      JOBS
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --jobs)    JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)  JOBS="${1#*=}"; shift ;;
        --clean)   CLEAN=1; shift ;;
        --arch)    ARCH="${2:?--arch needs a value}"; shift 2 ;;
        --arch=*)  ARCH="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         die "unknown argument '$1' (see --help)" ;;
    esac
done

ffmpeg_validate_jobs
require_ffmpeg_src
[ "$ARCH" = "x86_64" ] || die "build-windows.sh only supports --arch x86_64 (contract §5 target windows-x64)"

HOST="$(uname -s)"
case "$HOST" in
    MINGW*|MSYS*|CYGWIN*)
        NATIVE=1
        CC="${CC:-gcc}"
        CROSS_PREFIX="${CROSS_PREFIX:-}"
        ;;
    Linux)
        NATIVE=0
        CROSS_PREFIX="${CROSS_PREFIX:-x86_64-w64-mingw32-}"
        CC="${CC:-${CROSS_PREFIX}gcc}"
        ;;
    *)
        die "unsupported host '$HOST' — run under MSYS2/Git-Bash on Windows, or use Linux with mingw-w64"
        ;;
esac

require_cmd "$CC" "install mingw-w64 (e.g. 'pacman -S mingw-w64-gcc' / 'apt install gcc-mingw-w64-x86-64') or set CC="
if [ "$NATIVE" = "0" ]; then
    require_cmd "${CROSS_PREFIX}ar" "mingw-w64 binutils missing (${CROSS_PREFIX}ar)"
    require_cmd "${CROSS_PREFIX}strip" "mingw-w64 binutils missing (${CROSS_PREFIX}strip)"
fi
KIND="$(ffmpeg_compiler_kind "$CC")"

builddir="$(ffmpeg_builddir "$TARGET")"
distdir="$(ffmpeg_distdir "$TARGET")"
ffmpeg_check_target_name "$TARGET"
mkdir -p "$distdir"

ffmpeg_banner "$TARGET"
if [ "$NATIVE" = "1" ]; then
    log "host: $HOST (native MSYS2 build)"
else
    log "host: $HOST (cross build with ${CROSS_PREFIX}gcc)"
fi
log "compiler: $CC ($KIND)"

if [ "$CLEAN" = "1" ]; then
    ffmpeg_reset_builddir "$builddir"
fi

args=( "${FFMPEG_BASE_FLAGS[@]}" )
args+=( --prefix="$builddir/prefix" --target-os=mingw32 --arch="$ARCH" --cc="$CC" )

if [ "$NATIVE" = "0" ]; then
    args+=( --enable-cross-compile --cross-prefix="$CROSS_PREFIX" )
fi

# LTO policy (contract §3): GCC -> --enable-lto + -flto=auto at link.
lto_cfg="$(ffmpeg_lto_configure_flags "$KIND")"
if [ -n "$lto_cfg" ]; then
    args+=( "$lto_cfg" )
fi

# -static: produce a self-contained exe (no libwinpthread/libgcc DLLs to ship).
ldflags="-static"
lto_ld="$(ffmpeg_lto_link_flags "$KIND")"
if [ -n "$lto_ld" ]; then
    ldflags="$lto_ld $ldflags"
fi
args+=( --extra-ldflags="$ldflags" )
log "extra ldflags: $ldflags"

if ffmpeg_zlib_available "$CC"; then
    args+=( --enable-zlib )
    log "zlib: enabled"
else
    log "zlib: not available in the mingw sysroot, skipping --enable-zlib (contract §4)"
fi

if ffmpeg_has_x86asm; then
    log "x86 asm: enabled ($(command -v nasm || command -v yasm))"
else
    warn "nasm/yasm not found — building with --disable-x86asm (slower SIMD, valid output)"
    args+=( --disable-x86asm )
fi

while IFS= read -r flag; do
    [ -n "$flag" ] && args+=( "$flag" )
done < <(ffmpeg_program_flags)

start="$(date +%s)"
ffmpeg_configure "$builddir" "${args[@]}"
ffmpeg_assert_license "$builddir"
ffmpeg_make "$builddir"

src="$builddir/ffmpeg.exe"
[ -f "$src" ] || die "make finished but '$src' is missing"
dst="$distdir/ffmpeg.exe"
ffmpeg_copy_artifact "$src" "$dst" 0755

if command -v file >/dev/null 2>&1; then
    ftype="$(file -b "$dst")"
    case "$ftype" in
        *PE32+*) log "file: $ftype" ;;
        *) warn "file(1) does not report PE32+: $ftype" ;;
    esac
fi

# Verify on the host: natively on Windows, or via wine on Linux (best effort).
first=""
if [ "$NATIVE" = "1" ]; then
    if out="$("$dst" -version 2>/dev/null | head -n1)" && [ -n "$out" ]; then
        first="$out"
    fi
elif command -v wine >/dev/null 2>&1; then
    if out="$(WINEDEBUG=-all timeout 180 wine "$dst" -version 2>/dev/null | head -n1)" && [ -n "$out" ]; then
        first="$out"
    else
        warn "wine could not run the cross-built exe (best-effort check only)"
    fi
else
    log "wine not installed — skipping host execution check for the cross build"
fi

if [ -n "$first" ]; then
    printf '%s\n' "$first" > "$distdir/version.txt"
    printf '\n[ffmpeg] %s: artifact -version first line:\n  %s\n' "$TARGET" "$first"
    ffmpeg_require_version_line "$dst" "$(ffmpeg_tag)"
else
    printf 'ffmpeg version %s (cross-compiled for %s)\n' "$(ffmpeg_tag)" "$TARGET" > "$distdir/version.txt"
    warn "version.txt uses the cross-compile fallback; run '$dst -version' on Windows to confirm"
fi

ffmpeg_report_artifact "$dst"
log "$TARGET build complete in $(ffmpeg_elapsed "$start")"
log "dist: $distdir"
