#!/usr/bin/env bash
# =============================================================================
# build-deps.sh — build the third-party libraries FFmpeg_EXTERNAL_LIBS links.
#
#   scripts/ffmpeg/build-deps.sh [--only lame,nvcodec] [--prefix DIR] [--jobs N]
#
# The libraries FFmpeg links live in build/ffmpeg/deps/<target>/; configure is
# pointed at that prefix by external-libs.sh. Recipes are plain autotools/cmake
# builds and honour CC, CFLAGS, LDFLAGS and --host, so the same script works for
# a cross toolchain when those are set.
#
# Sources are downloaded into build/ffmpeg/deps/src and kept between runs.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

ONLY=""
PREFIX="${FFMPEG_DEPS_PREFIX:-$FFMPEG_BUILD_ROOT/deps/$(ffmpeg_deps_target)}"
SRC="$FFMPEG_BUILD_ROOT/deps/src"
JOBS="${JOBS:-$(ffmpeg_default_jobs)}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--only a,b] [--prefix DIR] [--jobs N]

Builds, into \$PREFIX:
  nvcodec   nv-codec-headers (headers only; enables --enable-nvenc)
  lame      LAME 3.100      (enables --enable-libmp3lame)
  svtav1    SVT-AV1         (enables --enable-libsvtav1, skipped when the
                             sysroot already provides SvtAv1Enc)

Cross builds: set CC/CFLAGS/LDFLAGS and pass --host <triple> through HOST=.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --only)   ONLY="${2:?--only needs a value}"; shift 2 ;;
        --only=*) ONLY="${1#*=}"; shift ;;
        --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        --jobs)   JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*) JOBS="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument '$1'" ;;
    esac
done

ffmpeg_validate_jobs
mkdir -p "$PREFIX" "$SRC"

want() {
    case ",$ONLY," in
        ",,") return 0 ;;
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

fetch() { # fetch <url> <file>
    [ -f "$SRC/$2" ] && return 0
    log "download $2"
    curl -fsSL -o "$SRC/$2.part" "$1"
    mv "$SRC/$2.part" "$SRC/$2"
}

unpack() { # unpack <file> <dir>
    [ -d "$SRC/$2" ] && return 0
    log "unpack $1"
    mkdir -p "$SRC/$2"
    tar -xf "$SRC/$1" -C "$SRC/$2" --strip-components=1
}

build_nvcodec() {
    fetch https://github.com/FFmpeg/nv-codec-headers/releases/download/n13.0.19.0/nv-codec-headers-13.0.19.0.tar.gz nv-codec-headers.tar.gz
    unpack nv-codec-headers.tar.gz nv-codec-headers
    log "build nv-codec-headers"
    make -C "$SRC/nv-codec-headers" -j"$JOBS" install PREFIX="$PREFIX"
}

build_lame() {
    fetch https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz lame-3.100.tar.gz
    unpack lame-3.100.tar.gz lame-3.100
    log "build lame 3.100"
    ( cd "$SRC/lame-3.100" && ./configure \
        --prefix="$PREFIX" \
        --disable-shared --enable-static \
        --disable-frontend \
        ${HOST:+--host="$HOST"} \
        ${CC:+CC="$CC"} >/dev/null
      make -j"$JOBS" >/dev/null
      make install >/dev/null )
}

build_svtav1() {
    if pkg-config --exists SvtAv1Enc 2>/dev/null; then
        log "SVT-AV1 from the sysroot ($(pkg-config --modversion SvtAv1Enc)); skipping"
        return 0
    fi
    fetch https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v2.3.0/SVT-AV1-v2.3.0.tar.gz SVT-AV1-2.3.0.tar.gz
    unpack SVT-AV1-2.3.0.tar.gz SVT-AV1
    log "build SVT-AV1 2.3.0"
    cmake -S "$SRC/SVT-AV1" -B "$SRC/SVT-AV1/build" -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DCOMPILE_C_ONLY=OFF >/dev/null
    cmake --build "$SRC/SVT-AV1/build" -j "$JOBS" >/dev/null
    cmake --install "$SRC/SVT-AV1/build" >/dev/null
}

for dep in nvcodec lame svtav1; do
    want "$dep" || continue
    "build_$dep"
done

log "dependencies installed into $PREFIX"
