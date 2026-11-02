#!/usr/bin/env bash
# =============================================================================
# common.sh — shared helpers for the rain_fui FFmpeg build scripts.
#
# Sourced by scripts/ffmpeg/build-*.sh and install-to-app.sh; never executed
# directly. Implements the shared parts of docs/build-contract.md:
#   §2 license assertion   §3 LTO policy   §4 configure baseline
#   §5 artifact layout     §6 environment variables / CLI conventions
#
# Environment variables (contract §6):
#   FFMPEG_SRC          FFmpeg source tree      (default <repo>/third_party/ffmpeg)
#   FFMPEG_BUILD_ROOT   build tree root         (default <repo>/build/ffmpeg)
#   FFMPEG_DIST         artifact root           (default <repo>/build/ffmpeg/dist)
#   JOBS                parallel make jobs      (default nproc / NUMBER_OF_PROCESSORS)
#   FFMPEG_LTO          1 = LTO on, 0 = off     (default 1; debug only)
#   FFMPEG_WITH_FFPROBE 1 = also build ffprobe  (default 0)
#   FFMPEG_EXTERNAL_LIBS 1 = link third-party codecs and hardware back ends
#                            (default 0: native encoders only)
#   FFMPEG_DEPS_PREFIX   dependency prefix      (default build/ffmpeg/deps/<target>)
# =============================================================================
# shellcheck shell=bash

if [ "${FFMPEG_COMMON_LOADED:-0}" = "1" ]; then
    return 0
fi
FFMPEG_COMMON_LOADED=1

FFMPEG_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$FFMPEG_SCRIPT_DIR/../.." && pwd -P)"
export REPO_ROOT

FFMPEG_SRC="${FFMPEG_SRC:-$REPO_ROOT/third_party/ffmpeg}"
FFMPEG_BUILD_ROOT="${FFMPEG_BUILD_ROOT:-$REPO_ROOT/build/ffmpeg}"
FFMPEG_FFBUILD="${FFMPEG_FFBUILD:-$FFMPEG_BUILD_ROOT/ffbuild}"
FFMPEG_DIST="${FFMPEG_DIST:-$FFMPEG_BUILD_ROOT/dist}"
FFMPEG_LTO="${FFMPEG_LTO:-1}"
FFMPEG_WITH_FFPROBE="${FFMPEG_WITH_FFPROBE:-0}"
FFMPEG_EXTERNAL_LIBS="${FFMPEG_EXTERNAL_LIBS:-0}"

# shellcheck source=scripts/ffmpeg/external-libs.sh
source "$FFMPEG_SCRIPT_DIR/external-libs.sh"

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
log()  { printf '[ffmpeg] %s\n' "$*"; }
warn() { printf '[ffmpeg] WARNING: %s\n' "$*" >&2; }
die()  { printf '[ffmpeg] ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# preconditions
# ---------------------------------------------------------------------------
# require_cmd <cmd> [hint]
require_cmd() {
    local cmd="$1" hint="${2:-}"
    command -v "$cmd" >/dev/null 2>&1 && return 0
    die "required command '$cmd' not found.${hint:+ $hint}"
}

# ffmpeg_has_x86asm: true when nasm (or yasm) is usable. nasm installed in
# ~/.local/bin (built without root) is picked up automatically.
ffmpeg_has_x86asm() {
    local cand
    for cand in "$HOME/.local/bin/nasm" "$HOME/.local/bin/yasm"; do
        if [ -x "$cand" ] && ! command -v "$(basename "$cand")" >/dev/null 2>&1; then
            PATH="$(dirname "$cand"):$PATH"
            export PATH
            log "using $(basename "$cand") from $(dirname "$cand")"
        fi
    done
    command -v nasm >/dev/null 2>&1 || command -v yasm >/dev/null 2>&1
}

# require_ffmpeg_src: FFmpeg checkout present and versioned by RELEASE.
require_ffmpeg_src() {
    [ -f "$FFMPEG_SRC/configure" ] || die \
        "FFmpeg source not found at '$FFMPEG_SRC' — run: git submodule update --init --recursive"
    [ -f "$FFMPEG_SRC/RELEASE" ] || die \
        "'$FFMPEG_SRC/RELEASE' missing — not a complete FFmpeg checkout (run: git submodule update --init --recursive)"
    case "$FFMPEG_SRC" in
        "$REPO_ROOT"/third_party/ffmpeg*) ;;
        *) warn "FFMPEG_SRC is outside third_party/ffmpeg: $FFMPEG_SRC" ;;
    esac
    log "source: $FFMPEG_SRC (FFmpeg $(ffmpeg_tag))"
}

# ffmpeg_tag: release version from the checked out source (e.g. 9.0.2).
ffmpeg_tag() {
    tr -d '[:space:]' < "$FFMPEG_SRC/RELEASE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# jobs / timing
# ---------------------------------------------------------------------------
ffmpeg_default_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif [ -n "${NUMBER_OF_PROCESSORS:-}" ]; then
        printf '%s\n' "$NUMBER_OF_PROCESSORS"
    else
        printf '4\n'
    fi
}

ffmpeg_validate_jobs() {
    case "${JOBS:-}" in
        ''|*[!0-9]*) die "JOBS must be a positive integer (got '${JOBS:-}')" ;;
    esac
    [ "$JOBS" -ge 1 ] || die "JOBS must be >= 1 (got '$JOBS')"
}

JOBS="${JOBS:-$(ffmpeg_default_jobs)}"

# ffmpeg_elapsed <start_epoch>: human readable wall time.
ffmpeg_elapsed() {
    local start="${1:-0}" now secs
    now="$(date +%s)"
    secs=$(( now - start ))
    printf '%dm%02ds' $(( secs / 60 )) $(( secs % 60 ))
}

# ---------------------------------------------------------------------------
# contract §4 — shared configure baseline
# ---------------------------------------------------------------------------
# ffmpeg_base_flags: one line of configure flags shared by every target.
ffmpeg_base_flags() {
    printf '%s\n' \
        "--disable-doc --disable-debug --disable-shared --enable-static" \
        "--disable-autodetect --enable-gpl --enable-version3" \
        "--enable-pic --disable-ffplay"
}

# shellcheck disable=SC2207
FFMPEG_BASE_FLAGS=( $(ffmpeg_base_flags) )

# ffmpeg_program_flags: build only the `ffmpeg` program by default.
# ffprobe is optional per contract §5 and costs build time + dist files.
ffmpeg_program_flags() {
    if [ "$FFMPEG_WITH_FFPROBE" = "1" ]; then
        return 0
    fi
    printf '%s\n' --disable-ffprobe
}

# ---------------------------------------------------------------------------
# contract §3 — LTO policy
# ---------------------------------------------------------------------------
# ffmpeg_compiler_kind <cc ...>: "clang" or "gcc" (based on --version output).
ffmpeg_compiler_kind() {
    local cc="$1" out
    out="$("$cc" --version 2>/dev/null || true)"
    out="${out%%$'\n'*}"
    case "$out" in
        *clang*|*Clang*|*"Apple LLVM"*) printf 'clang\n' ;;
        *)                              printf 'gcc\n' ;;
    esac
}

# ffmpeg_lto_configure_flags <gcc|clang|emcc>: configure-time LTO argument.
# GCC only accepts bare --enable-lto (= -flto); clang/emcc get explicit full LTO.
ffmpeg_lto_configure_flags() {
    if [ "${FFMPEG_LTO:-1}" = "0" ]; then
        return 0
    fi
    case "${1:-gcc}" in
        gcc)          printf '%s\n' --enable-lto ;;
        clang|emcc)   printf '%s\n' --enable-lto=full ;;
        *)            die "ffmpeg_lto_configure_flags: unknown compiler kind '$1'" ;;
    esac
}

# ffmpeg_lto_link_flags <gcc|clang|emcc>: extra LDFLAGS for the link step.
# GCC: -flto=auto lets the LTO back end share make's jobserver. clang/emcc
# already put -flto=full in LDFLAGS via configure, nothing to add.
ffmpeg_lto_link_flags() {
    if [ "${FFMPEG_LTO:-1}" = "0" ]; then
        return 0
    fi
    case "${1:-gcc}" in
        gcc) printf '%s\n' "-flto=auto" ;;
        clang|emcc) ;;
        *) die "ffmpeg_lto_link_flags: unknown compiler kind '$1'" ;;
    esac
}

# ---------------------------------------------------------------------------
# Reminder printed by every build: dist/ is not what the app loads.
ffmpeg_remind_install() {
    log "the app tree still has the previous binary until you run:"
    log "  scripts/ffmpeg/install-to-app.sh $1"
}

# helpers: zlib probe, build layout, configure, make
# ---------------------------------------------------------------------------
# ffmpeg_zlib_available <cc> [extra compiler flags...]
# Contract §4: enable zlib only when the target sysroot actually provides it.
ffmpeg_zlib_available() {
    local cc="$1"
    shift
    printf '#include <zlib.h>\nint main(void){return (int)zlibVersion()[0];}\n' \
        | "$cc" "$@" -x c - -c -o /dev/null >/dev/null 2>&1
}

# ffmpeg_builddir <target> / ffmpeg_distdir <target> (contract §5)
ffmpeg_builddir() { printf '%s/%s\n' "$FFMPEG_FFBUILD" "$1"; }
ffmpeg_distdir()  { printf '%s/%s\n' "$FFMPEG_DIST" "$1"; }

# ffmpeg_check_target_name <target>
ffmpeg_check_target_name() {
    case "$1" in
        ''|*/*|.*) die "invalid target name '$1'" ;;
    esac
}

# ffmpeg_reset_builddir <dir>: rm -rf but only inside <build>/ffbuild.
ffmpeg_reset_builddir() {
    local dir="$1"
    case "$dir" in
        "$FFMPEG_FFBUILD"/*) ;;
        *) die "refusing to remove '$dir' (outside $FFMPEG_FFBUILD)" ;;
    esac
    log "cleaning $dir"
    rm -rf -- "$dir"
}

# ffmpeg_configure <builddir> <configure args...>
# Out-of-tree: configure runs with CWD = builddir, source stays untouched.
ffmpeg_configure() {
    local builddir="${1:?ffmpeg_configure: builddir required}"
    shift
    case "$builddir" in
        "$FFMPEG_SRC"|"$FFMPEG_SRC"/*) die "build dir must be outside the source tree: $builddir" ;;
    esac
    mkdir -p "$builddir"
    printf '%s\n' "$@" > "$builddir/configure.args"
    log "configure ($# args) in $builddir"
    ( cd "$builddir" && "$FFMPEG_SRC/configure" "$@" )
}

# ffmpeg_make <builddir> [targets...]
ffmpeg_make() {
    local builddir="${1:?ffmpeg_make: builddir required}"
    shift
    log "make -j$JOBS $*"
    make -C "$builddir" -j"$JOBS" "$@"
}

# ffmpeg_assert_license <builddir> — contract §2 hard gate.
ffmpeg_assert_license() {
    local builddir="${1:?}" mak config_h
    mak="$builddir/ffbuild/config.mak"
    config_h="$builddir/config.h"
    [ -f "$mak" ] || die "license check: '$mak' not found (configure did not finish?)"

    grep -qx 'CONFIG_GPL=yes' "$mak" \
        || die "license check FAILED: CONFIG_GPL is not 'yes' in $mak (contract §2 requires --enable-gpl)"
    grep -qx 'CONFIG_VERSION3=yes' "$mak" \
        || die "license check FAILED: CONFIG_VERSION3 is not 'yes' in $mak (contract §2 requires --enable-version3)"
    if grep -qx 'CONFIG_NONFREE=yes' "$mak" || { [ -f "$config_h" ] && grep -q '^#define CONFIG_NONFREE 1' "$config_h"; }; then
        die "license check FAILED: CONFIG_NONFREE is enabled in $builddir (contract §2 forbids nonfree components)"
    fi
    log "license check: GPL=yes VERSION3=yes NONFREE=no"
}

# ---------------------------------------------------------------------------
# artifacts
# ---------------------------------------------------------------------------
# ffmpeg_copy_artifact <src> <dst> [mode]
ffmpeg_copy_artifact() {
    local src="$1" dst="$2" mode="${3:-0755}"
    [ -f "$src" ] || die "artifact '$src' missing"
    mkdir -p "$(dirname "$dst")"
    install -m "$mode" "$src" "$dst"
    log "installed $(basename "$src") -> $dst"
}

# ffmpeg_report_artifact <path>: size + file(1) type, for build logs/reports.
ffmpeg_report_artifact() {
    local path="$1" size type
    [ -f "$path" ] || { warn "artifact '$path' missing"; return 1; }
    size="$(wc -c < "$path" | tr -d ' ')"
    if command -v file >/dev/null 2>&1; then
        type="$(file -b "$path")"
    else
        type="(file(1) unavailable)"
    fi
    printf '[ffmpeg] artifact: %s\n' "$path"
    printf '[ffmpeg]   size: %s bytes\n' "$size"
    printf '[ffmpeg]   type: %s\n' "$type"
}

# ffmpeg_version_file <binary|""> <version.txt> [fallback first line]
# Writes the first line of `<binary> -version` (contract §5). Cross-compiled
# binaries that the host cannot execute fall back to the caller's text.
# Prints the chosen line.
ffmpeg_version_file() {
    local bin="${1:-}" out="${2:?version.txt path required}" fallback="${3:-}"
    local text first tag
    tag="$(ffmpeg_tag)"
    first=""
    if [ -n "$bin" ] && [ -f "$bin" ] && [ -x "$bin" ]; then
        text="$("$bin" -version 2>&1 || true)"
        first="${text%%$'\n'*}"
    fi
    if [ -z "$first" ] && [ -n "$fallback" ]; then
        first="$fallback"
    fi
    [ -n "$first" ] || die "cannot determine FFmpeg version for '$bin' (not runnable and no fallback given)"
    case "$first" in
        *"$tag"*) ;;
        *) warn "version line does not mention $tag: $first" ;;
    esac
    mkdir -p "$(dirname "$out")"
    printf '%s\n' "$first" > "$out"
    printf '%s\n' "$first"
}

# ffmpeg_require_version_line <binary> <expected tag> — contract §9.3.
ffmpeg_require_version_line() {
    local bin="$1" tag="$2" text first
    text="$("$bin" -version 2>&1 || true)"
    first="${text%%$'\n'*}"
    case "$first" in
        *"$tag"*) log "version check: $first" ;;
        *) die "version check FAILED for '$bin': expected '$tag', got '${first:-<no output>}'" ;;
    esac
}

# ffmpeg_banner <target> — one-line build header.
ffmpeg_banner() {
    printf '\n[ffmpeg] ============================================================\n'
    printf '[ffmpeg] building target: %s\n' "$1"
    printf '[ffmpeg] jobs: %s  lto: %s  date: %s\n' \
        "$JOBS" "$([ "${FFMPEG_LTO:-1}" = "0" ] && echo off || echo on)" "$(date -Is)"
    printf '[ffmpeg] ============================================================\n'
}

# ffmpeg_usage_common — flags every build script understands.
ffmpeg_usage_common() {
    cat <<'EOF'
  -h, --help        show this help
      --jobs N      parallel compile jobs (default: nproc)
EOF
}
