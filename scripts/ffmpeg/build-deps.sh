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
TARGET="${FFMPEG_DEPS_TARGET:-linux-x64}"
PREFIX=""
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
  x264      x264            (enables --enable-libx264)
  opus      libopus         (enables --enable-libopus)
  ogg       libogg          (libvorbis needs it)
  vorbis    libvorbis       (enables --enable-libvorbis)
  vpx       libvpx          (enables --enable-libvpx)
  webp      libwebp         (enables --enable-libwebp)

Cross builds: pass --target android-arm64-v8a / android-armeabi-v7a /
android-x86_64 / windows-x64; the NDK or mingw toolchain is configured here, so
no CC/CFLAGS juggling is needed. HOST= still overrides the autoconf triple.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --only)   ONLY="${2:?--only needs a value}"; shift 2 ;;
        --only=*) ONLY="${1#*=}"; shift ;;
        --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        --target) TARGET="${2:?--target needs a value}"; shift 2 ;;
        --target=*) TARGET="${1#*=}"; shift ;;
        --jobs)   JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*) JOBS="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument '$1'" ;;
    esac
done

# The prefix follows --target, so an Android build never writes into the host
# prefix again.
if [ -z "$PREFIX" ]; then
    PREFIX="${FFMPEG_DEPS_PREFIX:-$FFMPEG_BUILD_ROOT/deps/$TARGET}"
fi

ffmpeg_validate_jobs
mkdir -p "$PREFIX" "$SRC"

# --- toolchain for a cross target -------------------------------------------
# Everything below is exported, so the recipes stay plain ./configure and
# cmake calls.
DEFAULT_NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/Android/Sdk/ndk/28.2.13676358}}"
CMAKE_TARGET_ARGS=()
case "$TARGET" in
    android-*)
        abi="${TARGET#android-}"
        case "$abi" in
            arm64-v8a) triple="aarch64-linux-android"; host="aarch64-linux-android" ;;
            armeabi-v7a) triple="armv7a-linux-androideabi"; host="armv7a-linux-androideabi" ;;
            x86_64) triple="x86_64-linux-android"; host="x86_64-linux-android" ;;
            *) die "unknown Android ABI '$abi'" ;;
        esac
        tc="$DEFAULT_NDK/toolchains/llvm/prebuilt/linux-x86_64"
        sysroot="$tc/sysroot"
        [ -d "$tc" ] || die "Android NDK not found at $DEFAULT_NDK"
        export CC="$tc/bin/${triple}24-clang"
        export CXX="$tc/bin/${triple}24-clang++"
        export AR="$tc/bin/llvm-ar"
        export RANLIB="$tc/bin/llvm-ranlib"
        export NM="$tc/bin/llvm-nm"
        export STRIP="$tc/bin/llvm-strip"
        export CFLAGS="--sysroot=$sysroot -fPIC -O2"
        export CXXFLAGS="$CFLAGS"
        export LDFLAGS="--sysroot=$sysroot"
        export HOST="$host"
        export ANDROID_TOOLCHAIN_PREFIX="$tc/bin/llvm-"
        export ANDROID_SYSROOT="$sysroot"
        CMAKE_TARGET_ARGS=(
            -DCMAKE_TOOLCHAIN_FILE="$DEFAULT_NDK/build/cmake/android.toolchain.cmake"
            -DANDROID_ABI="$abi"
            -DANDROID_PLATFORM=android-24
        )
        ;;
    windows-x64)
        command -v x86_64-w64-mingw32-gcc >/dev/null \
            || die "mingw-w64 is not installed (x86_64-w64-mingw32-gcc)"
        export CC=x86_64-w64-mingw32-gcc
        export CXX=x86_64-w64-mingw32-g++
        export AR=x86_64-w64-mingw32-ar
        export RANLIB=x86_64-w64-mingw32-ranlib
        export NM=x86_64-w64-mingw32-nm
        export STRIP=x86_64-w64-mingw32-strip
        export CFLAGS="-O2"
        export CXXFLAGS="$CFLAGS"
        export HOST=x86_64-w64-mingw32
        CMAKE_TARGET_ARGS=(
            -DCMAKE_SYSTEM_NAME=Windows
            -DCMAKE_C_COMPILER="$CC"
            -DCMAKE_CXX_COMPILER="$CXX"
            -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres
        )
        ;;
    linux-*)
        ;;
    *)
        die "unknown --target '$TARGET'"
        ;;
esac
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
log "deps target $TARGET -> $PREFIX"

# Static archives need their libm reference on the link line, and several of
# these .pc files only list it in Libs.private, which pkg-config --libs hides.
patch_pc_lm() {
    local pc
    for pc in "$PREFIX"/lib/pkgconfig/*.pc; do
        [ -f "$pc" ] || continue
        if ! grep -q '^Libs:.*-lm' "$pc"; then
            sed -i.bak 's|^\(Libs:.*\)$|\1 -lm|' "$pc" && rm -f "$pc.bak"
        fi
    done
    # libvorbis needs libogg on the same line; pkg-config hides it because it
    # is a private requirement.
    for pc in "$PREFIX"/lib/pkgconfig/vorbis*.pc; do
        [ -f "$pc" ] || continue
        grep -q -- "-logg" "$pc" || sed -i.bak 's|^\(Libs:.*\)$|\1 -logg|' "$pc" && rm -f "$pc.bak"
        case "$pc" in
            *vorbisenc.pc)
                grep -q -- "-lvorbis" "$pc" \
                    || sed -i.bak 's|^\(Libs:.*\)$|\1 -lvorbis|' "$pc"
                rm -f "$pc.bak"
                ;;
        esac
    done
}

# autotools writes its configuration into the source tree, so every target
# builds in its own copy; otherwise an ARM configure leaks into the next ABI.
srccopy() { # srccopy <name>
    local name="$1"
    local dst="$SRC/$name-$TARGET"
    if [ ! -d "$dst" ]; then
        cp -a "$SRC/$name" "$dst"
    fi
    printf '%s' "$dst"
}

cmake_build() { # cmake_build <source dir> <extra cmake args...>
    local source="$1"; shift
    local build="$source/build-$TARGET"
    cmake -S "$source" -B "$build" -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        "${CMAKE_TARGET_ARGS[@]}" \
        "$@" >/dev/null
    cmake --build "$build" -j "$JOBS" >/dev/null
    cmake --install "$build" >/dev/null
}

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
    curl -fsSL --connect-timeout 20 --max-time 900 --retry 3 --retry-delay 2 \
        -o "$SRC/$2.part" "$1"
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
    local dir
    dir="$(srccopy lame-3.100)"
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      ./configure \
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

build_x264() {
    fetch https://github.com/mirror/x264/archive/refs/heads/stable.tar.gz x264-stable.tar.gz
    unpack x264-stable.tar.gz x264
    log "build x264"
    local cross=()
    case "$TARGET" in
        android-*) cross=(--cross-prefix="$ANDROID_TOOLCHAIN_PREFIX" --sysroot="$ANDROID_SYSROOT") ;;
        windows-*) : ;;
        *) cross=(--host="$HOST") ;;
    esac
    local dir
    dir="$(srccopy x264)"
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      ./configure \
        --prefix="$PREFIX" \
        --enable-static --enable-pic --disable-cli \
        ${HOST:+--host="$HOST"} \
        "${cross[@]}" \
        --extra-cflags="${CFLAGS:-}" >/dev/null
      make -j"$JOBS" >/dev/null
      make install >/dev/null )
}

build_opus() {
    fetch https://github.com/xiph/opus/archive/refs/tags/v1.5.2.tar.gz opus-1.5.2.tar.gz
    unpack opus-1.5.2.tar.gz opus
    log "build libopus 1.5.2"
    cmake_build "$SRC/opus" \
        -DOPUS_BUILD_SHARED_LIBRARY=OFF \
        -DOPUS_BUILD_TESTING=OFF \
        -DOPUS_BUILD_PROGRAMS=OFF
    # The source archive has no git tag to read, so opus.pc claims version 0
    # and FFmpeg's `opus >= 1.1` check rejects it.
    local pc="$PREFIX/lib/pkgconfig/opus.pc"
    if [ -f "$pc" ]; then
        sed -i.bak -e 's/^Version:.*/Version: 1.5.2/' \
            -e 's/^\(Libs:.*\)$/\1 -lm/' "$pc" && rm -f "$pc.bak"
    fi
}

build_ogg() {
    fetch https://github.com/xiph/ogg/archive/refs/tags/v1.3.5.tar.gz libogg-1.3.5.tar.gz
    unpack libogg-1.3.5.tar.gz ogg
    log "build libogg 1.3.5"
    cmake_build "$SRC/ogg" -DBUILD_TESTING=OFF
}

build_vorbis() {
    fetch https://github.com/xiph/vorbis/archive/refs/tags/v1.3.7.tar.gz libvorbis-1.3.7.tar.gz
    unpack libvorbis-1.3.7.tar.gz vorbis
    log "build libvorbis 1.3.7"
    local dir
    dir="$(srccopy vorbis)"
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      { [ -x ./configure ] || ./autogen.sh >/dev/null; } && ./configure \
        --prefix="$PREFIX" \
        --disable-shared --enable-static \
        --with-ogg="$PREFIX" \
        ${HOST:+--host="$HOST"} \
        ${CC:+CC="$CC"} >/dev/null
      make -j"$JOBS" >/dev/null
      make install >/dev/null )
}

build_vpx() {
    fetch https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.0.tar.gz libvpx-1.15.0.tar.gz
    unpack libvpx-1.15.0.tar.gz vpx
    log "build libvpx 1.15.0"
    local vpx_target
    case "$TARGET" in
        android-arm64-v8a) vpx_target=arm64-android-gcc ;;
        # libvpx's armv7 target hands -march=armv7-a to the host assembler
        # under this NDK; the generic C build avoids the ARM asm path entirely.
        android-armeabi-v7a) vpx_target=generic-gnu ;;
        android-x86_64) vpx_target=x86_64-android-gcc ;;
        windows-x64) vpx_target=x86_64-win64-gcc ;;
        *) vpx_target=x86_64-linux-gcc ;;
    esac
    local vpx_extra=()
    local dir
    dir="$(srccopy vpx)"
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      ./configure \
        --target="$vpx_target" \
        "${vpx_extra[@]}" \
        --prefix="$PREFIX" \
        --disable-shared --enable-static --enable-pic \
        --disable-examples --disable-tools --disable-docs \
        --disable-unit-tests >/dev/null
      make -j"$JOBS" >/dev/null
      make install >/dev/null )
}

build_webp() {
    fetch https://github.com/webmproject/libwebp/archive/refs/tags/v1.5.0.tar.gz libwebp-1.5.0.tar.gz
    unpack libwebp-1.5.0.tar.gz webp
    log "build libwebp 1.5.0"
    cmake_build "$SRC/webp" \
        -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF \
        -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
        -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
        -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
        -DWEBP_BUILD_EXTRAS=OFF
}

for dep in nvcodec lame svtav1 x264 opus ogg vorbis vpx webp; do
    want "$dep" || continue
    "build_$dep"
done

patch_pc_lm
# Windows archives need winsock for getaddrinfo/inet_aton, which the Opus
# build calls even though the encoder never touches the network.
if [ -f "$PREFIX/lib/pkgconfig/opus.pc" ] && [ "$TARGET" = "windows-x64" ]; then
    grep -q -- "-lws2_32" "$PREFIX/lib/pkgconfig/opus.pc" \
        || sed -i.bak 's|^\(Libs:.*\)$|\1 -lws2_32|' "$PREFIX/lib/pkgconfig/opus.pc"
    rm -f "$PREFIX/lib/pkgconfig/opus.pc.bak"
fi

# libwebp's archive needs its sharpyuv helper, which is a separate archive.
if [ -f "$PREFIX/lib/pkgconfig/libwebp.pc" ]; then
    grep -q -- "-lsharpyuv" "$PREFIX/lib/pkgconfig/libwebp.pc" \
        || sed -i.bak 's|^\(Libs:.*\)$|\1 -lsharpyuv|' "$PREFIX/lib/pkgconfig/libwebp.pc"
    rm -f "$PREFIX/lib/pkgconfig/libwebp.pc.bak"
fi

# x264's static archive pulls in pthread; the .pc only names the archive.
# bionic has no separate libpthread, so only non-Android targets get it.
if [ -f "$PREFIX/lib/pkgconfig/x264.pc" ]; then
    case "$TARGET" in
        android-*) sed -i.bak 's| -lpthread||' "$PREFIX/lib/pkgconfig/x264.pc" ;;
        *)
            grep -q -- "-lpthread" "$PREFIX/lib/pkgconfig/x264.pc" \
                || sed -i.bak 's|^\(Libs:.*\)$|\1 -lpthread|' "$PREFIX/lib/pkgconfig/x264.pc"
            ;;
    esac
    rm -f "$PREFIX/lib/pkgconfig/x264.pc.bak"
fi

# libvorbisenc archives reference libvorbis symbols; pkg-config only reports
# private requirements, so name the archive on the Libs line.
for pc in "$PREFIX"/lib/pkgconfig/vorbisenc.pc; do
    [ -f "$pc" ] || continue
    grep -q -- "-lvorbis" "$pc" || sed -i.bak 's|^\(Libs:.*\)$|\1 -lvorbis|' "$pc"
    rm -f "$pc.bak"
done

log "dependencies installed into $PREFIX"
