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
android-x86_64 / windows-x64 / macos-arm64 / macos-x64 / web-wasm; the NDK,
mingw, Xcode or Emscripten toolchain is configured here, so no CC/CFLAGS
juggling is needed. HOST= still overrides the autoconf triple.
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
        # MSYS2 的 MINGW64 环境里，binutils 可能只装成 ar/ranlib/nm/strip（不带
        # 三元组前缀），而 gcc 是带前缀的。写死 x86_64-w64-mingw32-ar 时 libtool
        # 会报 "x86_64-w64-mingw32-ar: command not found"（CI 上 LAME 就是这么死的），
        # 所以每个工具都先找带前缀的，再退回不带前缀的。
        pick_tool() {
            local candidate
            for candidate in "$@"; do
                if command -v "$candidate" >/dev/null 2>&1; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
            return 1
        }
        # `export VAR="$(cmd)"` hides cmd's exit status, so assign first and
        # export after the check; otherwise an empty CC would surface much later
        # as a confusing configure failure.
        CC="$(pick_tool x86_64-w64-mingw32-gcc gcc)" \
            || die "mingw-w64 is not installed (no x86_64-w64-mingw32-gcc / gcc)"
        CXX="$(pick_tool x86_64-w64-mingw32-g++ g++)" \
            || die "mingw-w64 is not installed (no x86_64-w64-mingw32-g++ / g++)"
        AR="$(pick_tool x86_64-w64-mingw32-ar ar)" || die "no ar for mingw-w64"
        RANLIB="$(pick_tool x86_64-w64-mingw32-ranlib ranlib)" \
            || die "no ranlib for mingw-w64"
        NM="$(pick_tool x86_64-w64-mingw32-nm nm)" || NM=""
        STRIP="$(pick_tool x86_64-w64-mingw32-strip strip)" || STRIP=""
        export CC CXX AR RANLIB NM STRIP
        export CFLAGS="-O2"
        export CXXFLAGS="$CFLAGS"
        export HOST=x86_64-w64-mingw32
        # x264/vpx 会调用 ${cross_prefix}windres，导出 RC 让它用我们找到的那个。
        RC="$(pick_tool x86_64-w64-mingw32-windres windres)" || RC=""
        export RC
        RC_COMPILER="$RC"
        CMAKE_TARGET_ARGS=(
            -DCMAKE_SYSTEM_NAME=Windows
            -DCMAKE_C_COMPILER="$CC"
            -DCMAKE_CXX_COMPILER="$CXX"
        )
        if [ -n "$RC_COMPILER" ]; then
            CMAKE_TARGET_ARGS+=( -DCMAKE_RC_COMPILER="$RC_COMPILER" )
        fi
        ;;
    web-wasm)
        local_emcc="$(command -v emcc || true)"
        if [ -z "$local_emcc" ]; then
            die "emcc not found; source \$HOME/emsdk/emsdk_env.sh first"
        fi
        export CC=emcc CXX=em++ AR=emar RANLIB=emranlib NM=emnm
        export CFLAGS="-O3 -fPIC -pthread"
        export CXXFLAGS="$CFLAGS"
        export LDFLAGS="-pthread"
        export EM_CROSS=1
        export HOST=x86_64-linux-gnu
        CMAKE_TARGET_ARGS=(
            -DCMAKE_TOOLCHAIN_FILE="$(dirname "$local_emcc")/cmake/Modules/Platform/Emscripten.cmake"
        )
        ;;
    macos-*)
        # 一个 runner 上同时给 arm64 和 x86_64 编依赖，只能靠 -arch 区分；SDK 路径
        # 和部署目标都显式给出，否则 Homebrew 的头文件会被混进来。
        arch="${TARGET#macos-}"
        case "$arch" in
            arm64)  triple="aarch64-apple-darwin" ;;
            x86_64) triple="x86_64-apple-darwin" ;;
            *) die "unknown macOS arch '$arch' (expected macos-arm64 / macos-x64)" ;;
        esac
        require_cmd xcrun "install Xcode or the command line tools"
        sdk="$(xcrun --sdk macosx --show-sdk-path)"
        macmin="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
        export MACOSX_DEPLOYMENT_TARGET="$macmin"
        CC="$(xcrun --sdk macosx --find clang)" || die "no clang in the macOS SDK"
        CXX="$(xcrun --sdk macosx --find clang++)" || die "no clang++ in the macOS SDK"
        export CC CXX
        # Xcode 15+ 的 clang 把「隐式函数声明」当错误（C99 起本就应该），而
        # LAME 3.100 / libvorbis 这类 2000 年代的 autotools 源码正是靠隐式声明
        # 过日子的；只降级这条诊断，别的错误照旧。
        export CFLAGS="-O2 -arch $arch -isysroot $sdk -mmacosx-version-min=$macmin -Wno-implicit-function-declaration"
        export CXXFLAGS="$CFLAGS"
        export LDFLAGS="-arch $arch -isysroot $sdk -mmacosx-version-min=$macmin"
        export HOST="$triple"
        CMAKE_TARGET_ARGS=(
            -DCMAKE_OSX_ARCHITECTURES="$arch"
            -DCMAKE_OSX_SYSROOT="$sdk"
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$macmin"
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

# Emscripten needs its cmake wrapper for the toolchain and its configure
# wrapper so configure does not try to run the produced binaries.
em_cmake() {
    if [ "${EM_CROSS:-0}" = "1" ]; then
        emcmake cmake "$@"
    else
        cmake "$@"
    fi
}

# autotools writes its configuration into the source tree, so every target
# builds in its own copy; otherwise an ARM configure leaks into the next ABI.
srccopy() { # srccopy <name> <tarball>
    local name="$1" tarball="$2"
    local dst="$SRC/$name-$TARGET"
    if [ ! -d "$dst" ]; then
        # Extract fresh instead of copying a tree another target already
        # compiled in: x264 keeps per-architecture objects in subdirectories
        # that `make distclean` does not remove, and a wasm link then picks up
        # x86-64 objects.
        mkdir -p "$dst"
        tar -xf "$SRC/$tarball" -C "$dst" --strip-components=1
    fi
    printf '%s' "$dst"
}

cmake_build() { # cmake_build <source dir> <extra cmake args...>
    local source="$1"; shift
    local build="$source/build-$TARGET"
    local generator=(-G Ninja)
    if [ "${EM_CROSS:-0}" = "1" ]; then
        generator=(
            -G Ninja
            -DCMAKE_MAKE_PROGRAM="$(command -v ninja)"
            -DCMAKE_C_COMPILER=emcc
            -DCMAKE_CXX_COMPILER=em++
        )
    fi
    em_cmake -S "$source" -B "$build" "${generator[@]}" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        ${CMAKE_TARGET_ARGS[@]+"${CMAKE_TARGET_ARGS[@]}"} \
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
    dir="$(srccopy lame-3.100 lame-3.100.tar.gz)"
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      # ac_cv_func_bcopy=no：LAME 探测到 bcopy 就把 mpg123.h 里的 memcpy 改写成
      # bcopy(...)，而 macOS 的头文件不再声明 bcopy，新版 clang 直接报错退出。
      # 走 memcpy 分支完全等价，而且各平台一致。
      ac_cv_func_bcopy=no \
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
    if [ "$TARGET" = "linux-x64" ] && pkg-config --exists SvtAv1Enc 2>/dev/null; then
        log "SVT-AV1 from the sysroot ($(pkg-config --modversion SvtAv1Enc)); skipping"
        return 0
    fi
    fetch https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v2.3.0/SVT-AV1-v2.3.0.tar.gz SVT-AV1-2.3.0.tar.gz
    unpack SVT-AV1-2.3.0.tar.gz SVT-AV1
    log "build SVT-AV1 2.3.0"
    local c_only=OFF
    case "$TARGET" in
        linux-*) c_only=OFF ;;
        *) c_only=ON ;;
    esac
    cmake_build "$SRC/SVT-AV1" \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DCOMPILE_C_ONLY=$c_only
}

build_x265() {
    fetch https://bitbucket.org/multicoreware/x265_git/get/4.1.tar.gz x265-4.1.tar.gz
    unpack x265-4.1.tar.gz x265
    log "build x265 4.1"
    # x265 4.1 still asks CMake for two pre-3.0 policies; CMake 4 refuses them.
    sed -i -e 's/CMP0025 OLD/CMP0025 NEW/' -e 's/CMP0054 OLD/CMP0054 NEW/' \
        "$SRC/x265/source/CMakeLists.txt"
    # wasm32 looks like a 32-bit x86 to x265, which then adds -march=i686 and
    # em++ rejects it.
    sed -i 's/elseif(X86 AND NOT X64)$/elseif(X86 AND NOT X64 AND NOT EMSCRIPTEN)/' \
        "$SRC/x265/source/CMakeLists.txt"
    # Assembly is off for cross builds: it needs the target's assembler and the
    # NDK/mingw paths differ enough to be a project of its own.
    local asm=OFF
    case "$TARGET" in
        linux-*) asm=ON ;;
    esac
    cmake_build "$SRC/x265/source" \
        -DENABLE_CLI=OFF -DENABLE_SHARED=OFF -DENABLE_ASSEMBLY=$asm \
        -DENABLE_TESTS=OFF -DENABLE_PIC=ON -DEXPORT_C_API=ON
    # x265 does not always install a .pc file; FFmpeg's configure insists on
    # one, so write the few lines it needs.
    local pc="$PREFIX/lib/pkgconfig/x265.pc"
    local cxxlib=stdc++
    case "$TARGET" in
        android-*|web-wasm) cxxlib=c++ ;;
    esac
    # x265's own x265.pc names an archive with -l:libunwind.a, which FFmpeg's
    # static pkg-config mode turns into a broken -l-l: option; write a plain one.
    if true; then
        mkdir -p "$(dirname "$pc")"
        cat > "$pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: x265
Description: H.265/HEVC video encoder
Version: 4.1
Libs: -L\${libdir} -lx265 -l$cxxlib -lm
Cflags: -I\${includedir}
EOF
    fi
}

unpack_flat() { # unpack_flat <file> <dir>  (archives without a top directory)
    [ -d "$SRC/$2" ] && return 0
    log "unpack $1"
    mkdir -p "$SRC/$2"
    tar -xf "$SRC/$1" -C "$SRC/$2"
}

build_aom() {
    fetch https://deb.debian.org/debian/pool/main/a/aom/aom_3.14.1.orig.tar.xz aom-3.14.1.tar.xz
    unpack_flat aom-3.14.1.tar.xz aom
    log "build libaom 3.14.1"
    # aom's NEON/SVE translation units are memory hungry; 20 parallel clang
    # processes get OOM-killed on a 32 GB machine, 8 does not.
    local JOBS=8
    local cpu_args=()
    case "$TARGET" in
        android-arm64-v8a) cpu_args=(-DAOM_TARGET_CPU=arm64) ;;
        android-armeabi-v7a) cpu_args=(-DAOM_TARGET_CPU=generic) ;;
        android-x86_64|windows-x64|macos-x64) cpu_args=(-DAOM_TARGET_CPU=x86_64) ;;
        macos-arm64) cpu_args=(-DAOM_TARGET_CPU=arm64) ;;
        web-wasm) cpu_args=(-DAOM_TARGET_CPU=generic) ;;
    esac
    cmake_build "$SRC/aom" \
        -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_TOOLS=OFF \
        -DENABLE_DOCS=OFF -DCONFIG_PIC=1 -DENABLE_CCACHE=OFF \
        ${cpu_args[@]+"${cpu_args[@]}"}
}

build_zlib() {
    fetch https://github.com/madler/zlib/archive/refs/tags/v1.3.1.tar.gz zlib-1.3.1.tar.gz
    unpack zlib-1.3.1.tar.gz zlib
    log "build zlib 1.3.1"
    cmake_build "$SRC/zlib" -DZLIB_BUILD_EXAMPLES=OFF -DZLIB_BUILD_SHARED=OFF
    # zlib's CMake installs libzlibstatic.a; FFmpeg links -lz.
    local libdir="$PREFIX/lib"
    [ -d "$PREFIX/lib64" ] && libdir="$PREFIX/lib64"
    if [ -f "$libdir/libzlibstatic.a" ] && [ ! -f "$libdir/libz.a" ]; then
        cp "$libdir/libzlibstatic.a" "$libdir/libz.a"
    fi
}

build_x264() {
    fetch https://github.com/mirror/x264/archive/refs/heads/stable.tar.gz x264-stable.tar.gz
    unpack x264-stable.tar.gz x264
    log "build x264"
    local cross=()
    case "$TARGET" in
        android-*) cross=(--cross-prefix="$ANDROID_TOOLCHAIN_PREFIX" --sysroot="$ANDROID_SYSROOT") ;;
        windows-*)
            # x264 用 ${cross_prefix}ar 拼工具名。MSYS2 可能只装了不带三元组前缀的
            # binutils，此时传空前缀，让它退回 PATH 上的 ar/ranlib/windres。
            if command -v "${HOST:-x86_64-w64-mingw32}-ar" >/dev/null 2>&1; then
                cross=(--cross-prefix="${HOST:-x86_64-w64-mingw32}-")
            else
                cross=(--cross-prefix=)
            fi
            ;;

        # --host for wasm comes from HOST (set by the web-wasm toolchain block);
        # only the assembler has to be turned off here.
        web-wasm) cross=(--disable-asm) ;;
        # Native build: HOST is unset on purpose, and `--host "$HOST"` under
        # `set -u` is what made CI die at this line. configure guesses the host
        # itself when it is not told.
        *) : ;;
    esac
    local dir
    dir="$(srccopy x264 x264-stable.tar.gz)"
    # Emscripten has no sched_getaffinity; x264 already has a fallback for
    # Android, so route wasm through the same branch.
    if [ "${EM_CROSS:-0}" = "1" ]; then
        sed -i 's/^#ifdef __ANDROID__$/#if defined(__ANDROID__) || defined(__EMSCRIPTEN__)/' \
            "$dir/common/cpu.c"
    fi
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      ${EM_CROSS:+emconfigure} ./configure \
        --prefix="$PREFIX" \
        --enable-static --enable-pic --disable-cli \
        ${HOST:+--host="$HOST"} \
        ${cross[@]+"${cross[@]}"} \
        --extra-cflags="${CFLAGS:-}" >/dev/null
      # x264 adds -m64 for x86_64 hosts; under emcc that means wasm64 and the
      # archive then refuses to link against wasm32 objects.
      if [ "${EM_CROSS:-0}" = "1" ]; then
          sed -i -e 's/-m64//g' config.mak
      fi
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
    [ -f "$PREFIX/lib/libopus.a" ] || die "libopus 没有产出（$PREFIX/lib/libopus.a 缺失）"
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
    dir="$(srccopy vorbis libvorbis-1.3.7.tar.gz)"
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      { [ -x ./configure ] || ./autogen.sh >/dev/null; } && \
      ${EM_CROSS:+emconfigure} ./configure \
        --prefix="$PREFIX" \
        --disable-shared --enable-static \
        --with-ogg="$PREFIX" \
        ${HOST:+--host="$HOST"} \
        ${CC:+CC="$CC"} >/dev/null
      make -j"$JOBS" >/dev/null
      make install >/dev/null )
    [ -f "$PREFIX/lib/libvorbis.a" ] || die "libvorbis 没有产出（$PREFIX/lib/libvorbis.a 缺失）"
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
        macos-arm64) vpx_target=arm64-darwin-gcc ;;
        macos-x64) vpx_target=x86_64-darwin-gcc ;;
        web-wasm) vpx_target=generic-gnu ;;
        *) vpx_target=x86_64-linux-gcc ;;
    esac
    local vpx_extra=()
    local dir
    dir="$(srccopy vpx libvpx-1.15.0.tar.gz)"
    ( cd "$dir" && make distclean >/dev/null 2>&1 || true
      ${EM_CROSS:+emconfigure} ./configure \
        --target="$vpx_target" \
        ${vpx_extra[@]+"${vpx_extra[@]}"} \
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

for dep in nvcodec lame svtav1 x264 opus ogg vorbis vpx webp x265 aom zlib; do
    want "$dep" || continue
    # nv-codec-headers only makes sense where a CUDA driver exists; on android
    # and web the headers would just get --enable-nvenc added to a configure
    # line that cannot satisfy it.
    case "$dep:$TARGET" in
        nvcodec:android-*|nvcodec:web-wasm|nvcodec:ios-*)
            log "skip $dep (no use on $TARGET)"
            continue
            ;;
    esac
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
