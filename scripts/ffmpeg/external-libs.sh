#!/usr/bin/env bash
# =============================================================================
# external-libs.sh — third-party libraries for the "full" FFmpeg build.
#
# Sourced by common.sh. Nothing here runs unless FFMPEG_EXTERNAL_LIBS=1, so the
# default build stays the small native-only one.
#
#   FFMPEG_EXTERNAL_LIBS=1   link the libraries found in the dependency prefix
#                            and on the sysroot (opus, vorbis, vpx, x264, x265,
#                            aom, SVT-AV1, lame) plus the hardware back ends
#                            (nvenc, vaapi, libvpl/qsv, amf, mediacodec)
#   FFMPEG_DEPS_PREFIX       dependency prefix (default: build/ffmpeg/deps/<target>)
# =============================================================================

# Target name used for the default dependency prefix.
ffmpeg_deps_target() {
    printf '%s\n' "${FFMPEG_DEPS_TARGET:-linux-x64}"
}

ffmpeg_deps_prefix() {
    if [ -n "${FFMPEG_DEPS_PREFIX:-}" ]; then
        printf '%s\n' "$FFMPEG_DEPS_PREFIX"
        return
    fi
    printf '%s\n' "$FFMPEG_BUILD_ROOT/deps/$(ffmpeg_deps_target)"
}

# pkg-config inside the dependency prefix, falling back to the sysroot.
ffmpeg_deps_pkg_config_path() {
    local prefix="$1"
    printf '%s\n' "$prefix/lib/pkgconfig:$prefix/lib64/pkgconfig:$prefix/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
}

# Cross builds must not see the host's pkg-config: a host libopus would be
# linked into an Android or Windows binary. For those targets only the
# dependency prefix counts, and PKG_CONFIG_LIBDIR (not PATH) replaces the
# sysroot search path.
ffmpeg_have_pkg() {
    local pkg="$1" target_os="${2:-linux}" prefix="${3:-}"
    if [ "$target_os" = "linux" ]; then
        pkg-config --exists "$pkg" 2>/dev/null
        return
    fi
    PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/lib64/pkgconfig" \
    PKG_CONFIG_PATH="" \
        pkg-config --exists "$pkg" 2>/dev/null
}

# One "--enable-*" per line for every optional feature that can be built here.
# Nothing is guessed: each line is guarded by a probe of the actual headers or
# pkg-config file, because a configure flag for a missing library aborts the
# whole build.
ffmpeg_external_flags() {
    [ "${FFMPEG_EXTERNAL_LIBS:-0}" = "1" ] || return 0

    local target_os="${1:-linux}"
    local prefix
    prefix="$(ffmpeg_deps_prefix)"

    # Software encoders. pkg-config names are the ones the libraries ship.
    local pkg flag
    for pair in \
        "opus:--enable-libopus" \
        "vorbisenc:--enable-libvorbis" \
        "vpx:--enable-libvpx" \
        "x264:--enable-libx264" \
        "x265:--enable-libx265" \
        "aom:--enable-libaom" \
        "SvtAv1:--enable-libsvtav1" \
        "SvtAv1Enc:--enable-libsvtav1" \
        "mp3lame:--enable-libmp3lame" \
        "lame:--enable-libmp3lame" \
        "libwebp:--enable-libwebp"
    do
        pkg="${pair%%:*}"
        flag="${pair##*:}"
        if ffmpeg_have_pkg "$pkg" "$target_os" "$prefix"; then
            printf '%s\n' "$flag"
        fi
    done | awk '!seen[$0]++'

    # LAME ships no pkg-config file, so probe its header in the prefix.
    if [ -f "$prefix/include/lame/lame.h" ] \
       && ! pkg-config --exists mp3lame 2>/dev/null \
       && ! pkg-config --exists lame 2>/dev/null; then
        printf '%s\n' --enable-libmp3lame
    fi

    # Hardware back ends. nvenc only needs headers at build time; the runtime
    # needs a driver, and without one the encoder fails at Start with FFmpeg's
    # own message.
    if [ -f "$prefix/include/ffnvcodec/nvEncodeAPI.h" ] \
       || ffmpeg_have_pkg ffnvcodec "$target_os" "$prefix"; then
        # --disable-autodetect turns ffnvcodec off, so it has to be named.
        printf '%s\n' --enable-ffnvcodec --enable-nvenc
    fi
    if ffmpeg_have_pkg libva "$target_os" "$prefix"; then
        printf '%s\n' --enable-vaapi
    fi
    if ffmpeg_have_pkg vpl "$target_os" "$prefix"; then
        printf '%s\n' --enable-libvpl
    elif ffmpeg_have_pkg libmfx "$target_os" "$prefix"; then
        printf '%s\n' --enable-libmfx
    fi
    case "$target_os" in
        android)
            printf '%s\n' --enable-jni --enable-mediacodec
            ;;
        windows)
            if [ -f "$prefix/include/AMF/core/VideoEncoderFactory.h" ] \
               || [ -f "$prefix/include/AMF/videocodec.h" ]; then
                printf '%s\n' --enable-amf
            fi
            ;;
    esac
}

# Extra flags so configure can see a non-system prefix.
ffmpeg_external_extra_cflags() {
    [ "${FFMPEG_EXTERNAL_LIBS:-0}" = "1" ] || return 0
    local prefix
    prefix="$(ffmpeg_deps_prefix)"
    if [ -d "$prefix/include" ]; then
        printf '%s\n' "-I$prefix/include"
    fi
}

ffmpeg_external_extra_ldflags() {
    [ "${FFMPEG_EXTERNAL_LIBS:-0}" = "1" ] || return 0
    local prefix
    prefix="$(ffmpeg_deps_prefix)"
    local flags=""
    if [ -d "$prefix/lib" ]; then
        flags="-L$prefix/lib"
    fi
    if [ -d "$prefix/lib64" ]; then
        flags="$flags -L$prefix/lib64"
    fi
    printf '%s\n' "${flags# }"
}
