#!/usr/bin/env bash
# =============================================================================
# build.sh — interactive front door for the FFmpeg build scripts.
#
#   scripts/ffmpeg/build.sh                 # asks which targets to build
#   scripts/ffmpeg/build.sh --targets 1,4   # same selection, non-interactive
#   scripts/ffmpeg/build.sh --all           # every target (≈1 h on 20 cores)
#   scripts/ffmpeg/build.sh --list          # show the menu and exit
#
# A "target" is one self-contained FFmpeg build (contract §5) plus its copy
# into the Flutter app tree (contract §8). The individual build-<target>.sh
# scripts still work on their own; this script only orchestrates them, so CI
# keeps calling them directly.
#
# Windows: run this from an MSYS2 MinGW64 shell, like build-windows.sh itself.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

# Order matters: it is the menu order and the default --all order.
ALL_TARGETS=(linux-x64 windows-x64 android-arm64-v8a android-armeabi-v7a android-x86_64 web)
ALL_LABELS=(
    "Linux desktop (x86_64)"
    "Windows desktop (x86_64, MinGW)"
    "Android arm64-v8a (64-bit phones)"
    "Android armeabi-v7a (32-bit phones)"
    "Android x86_64 (emulators)"
    "Web (wasm, threaded)"
)

JOBS_ARG=""
API="24"
DO_INSTALL=1
CLEAN=0
DRY_RUN=0
ASSUME_YES=0
SELECTION=""
CHOSEN=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build one or more FFmpeg targets. Without --targets/--all and with a terminal
attached, the script asks which targets to build.

Options:
      --targets LIST   comma/space separated targets or menu numbers,
                       e.g. --targets 1,4 or --targets linux-x64,web
      --all            select every target
      --list           print the target list and exit
  -j, --jobs N         parallel compile jobs (default: $(ffmpeg_default_jobs))
      --api N          Android API level (default: $API)
      --clean          wipe each target's build directory before configuring
      --no-install     build only; do not copy artifacts into the app trees
      --dry-run        print the commands that would run, execute nothing
  -y, --yes            non-interactive: build every target when none is chosen
  -h, --help           show this help

Targets and aliases:
      linux, windows, web          single targets
      android                      all three Android ABIs
      all                          everything

Environment:
      JOBS                 parallel compile jobs (overridden by --jobs)
      FFMPEG_LTO=0         disable LTO
      ANDROID_NDK_HOME     NDK root for Android builds
      EMSDK                emsdk root for the web build
EOF
}

list_targets() {
    local i
    for i in "${!ALL_TARGETS[@]}"; do
        printf '  %d) %-22s %s\n' "$((i + 1))" "${ALL_TARGETS[$i]}" "${ALL_LABELS[$i]}"
    done
    printf '  a) %-22s %s\n' all "every target at once"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --targets)   SELECTION="${2:?--targets needs a value}"; shift 2 ;;
        --targets=*) SELECTION="${1#*=}"; shift ;;
        --all)       SELECTION="all"; shift ;;
        --list)      printf 'FFmpeg targets:\n'; list_targets; exit 0 ;;
        --jobs|-j)   JOBS_ARG="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)    JOBS_ARG="${1#*=}"; shift ;;
        --api)       API="${2:?--api needs a value}"; shift 2 ;;
        --api=*)     API="${1#*=}"; shift ;;
        --clean)     CLEAN=1; shift ;;
        --no-install) DO_INSTALL=0; shift ;;
        --dry-run)   DRY_RUN=1; shift ;;
        -y|--yes)    ASSUME_YES=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "unknown argument '$1' (see --help)" ;;
    esac
done

case "$API" in ''|*[!0-9]*) die "--api must be a number (got '$API')" ;; esac

# ---------------------------------------------------------------------------
# Selection parsing
# ---------------------------------------------------------------------------

# Append a canonical target to CHOSEN unless it is already there.
add_target() {
    local candidate="$1" existing
    for existing in ${CHOSEN[@]+"${CHOSEN[@]}"}; do
        [ "$existing" = "$candidate" ] && return 0
    done
    CHOSEN+=( "$candidate" )
}

# Validate a token in the *main* shell: expand_token runs inside a process
# substitution (a subshell), where die() would only end that subshell and the
# caller would report the much less useful "nothing selected" instead.
validate_token() {
    local token="$1"
    case "$token" in
        all|linux|windows|android|linux-x64|windows-x64|\
        android-arm64-v8a|android-armeabi-v7a|android-x86_64|web)
            return 0
            ;;
        [0-9]|[0-9][0-9])
            if [ "$token" -lt 1 ] || [ "$token" -gt "${#ALL_TARGETS[@]}" ]; then
                die "menu number '$token' is out of range (1-${#ALL_TARGETS[@]})"
            fi
            return 0
            ;;
        [0-9]*-[0-9]*)
            local lo="${token%%-*}" hi="${token#*-}"
            case "$lo$hi" in ''|*[!0-9]*) die "bad range '$token'" ;; esac
            [ "$lo" -le "$hi" ] || die "bad range '$token' (start > end)"
            [ "$hi" -le "${#ALL_TARGETS[@]}" ] \
                || die "range '$token' is out of range (1-${#ALL_TARGETS[@]})"
            return 0
            ;;
        *) die "unknown target '$token' (try --list)" ;;
    esac
}

# Expand one token (name, alias or menu number) into canonical target names.
expand_token() {
    local token="$1" index
    case "$token" in
        all)        printf '%s\n' "${ALL_TARGETS[@]}" ;;
        linux)      printf 'linux-x64\n' ;;
        windows)    printf 'windows-x64\n' ;;
        android)    printf '%s\n' android-arm64-v8a android-armeabi-v7a android-x86_64 ;;
        linux-x64|windows-x64|android-arm64-v8a|android-armeabi-v7a|android-x86_64|web)
            printf '%s\n' "$token" ;;
        [0-9]*-[0-9]*)
            local lo="${token%%-*}" hi="${token#*-}" n
            case "$lo$hi" in ''|*[!0-9]*) die "bad range '$token'" ;; esac
            [ "$lo" -le "$hi" ] || die "bad range '$token' (start > end)"
            [ "$hi" -le "${#ALL_TARGETS[@]}" ] || die "range '$token' is out of range (1-${#ALL_TARGETS[@]})"
            for ((n = lo; n <= hi; n++)); do
                printf '%s\n' "${ALL_TARGETS[$((n - 1))]}"
            done
            ;;
        [0-9]|[0-9][0-9])
            index="$((token - 1))"
            if [ "$index" -lt 0 ] || [ "$index" -ge "${#ALL_TARGETS[@]}" ]; then
                die "menu number '$token' is out of range (1-${#ALL_TARGETS[@]})"
            fi
            printf '%s\n' "${ALL_TARGETS[$index]}"
            ;;
        *) die "unknown target '$token' (try --list)" ;;
    esac
}

parse_selection() {
    local raw="${1//,/ }" token expanded
    for token in $raw; do
        validate_token "$token"
        while IFS= read -r expanded; do
            add_target "$expanded"
        done < <(expand_token "$token")
    done
}

# Parse an interactive answer: numbers, ranges ("2-4"), names, "a"/"all".
parse_menu_answer() {
    local raw q
    raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ',' ' ')"
    for q in $raw; do
        case "$q" in
            a|all)      add_target_loop_all; return 0 ;;
            [0-9]*-[0-9]*)
                local lo="${q%%-*}" hi="${q#*-}" i
                case "$lo$hi" in ''|*[!0-9]*) die "bad range '$q'" ;; esac
                [ "$lo" -ge 1 ] || die "range '$q' is out of range (1-${#ALL_TARGETS[@]})"
                [ "$lo" -le "$hi" ] || die "bad range '$q' (start > end)"
                [ "$hi" -le "${#ALL_TARGETS[@]}" ] || die "range '$q' is out of range (1-${#ALL_TARGETS[@]})"
                for ((i = lo; i <= hi; i++)); do add_target "${ALL_TARGETS[$((i - 1))]}"; done
                ;;
            [0-9]|[0-9][0-9])
                if [ "$q" -lt 1 ] || [ "$q" -gt "${#ALL_TARGETS[@]}" ]; then
                    die "menu number '$q' is out of range (1-${#ALL_TARGETS[@]})"
                fi
                add_target "${ALL_TARGETS[$((q - 1))]}"
                ;;
            *)
                validate_token "$q"
                local expanded
                while IFS= read -r expanded; do add_target "$expanded"; done < <(expand_token "$q")
                ;;
        esac
    done
}

add_target_loop_all() {
    local t
    for t in "${ALL_TARGETS[@]}"; do add_target "$t"; done
}

choose_interactively() {
    local answer
    printf '\nWhich FFmpeg targets should be built?\n\n' >&2
    list_targets >&2
    printf '\n' >&2
    while :; do
        printf 'Selection (e.g. "1 4", "2-4", or "a" for all; "q" to quit): ' >&2
        IFS= read -r answer || die "no selection (stdin closed)"
        case "$answer" in
            q|Q|quit|exit) log "nothing to do"; exit 0 ;;
        esac
        CHOSEN=()
        if [ -n "$(printf '%s' "$answer" | tr -d '[:space:]')" ]; then
            parse_menu_answer "$answer"
        fi
        if [ "${#CHOSEN[@]}" -gt 0 ]; then
            return 0
        fi
        warn "empty selection — pick at least one target"
    done
}

if [ -n "$SELECTION" ]; then
    parse_selection "$SELECTION"
elif [ "$ASSUME_YES" = "1" ]; then
    add_target_loop_all
elif [ -t 0 ]; then
    choose_interactively
else
    die "no targets selected and stdin is not a terminal; pass --targets LIST or --all (see --list)"
fi

[ "${#CHOSEN[@]}" -gt 0 ] || die "nothing selected"

# ---------------------------------------------------------------------------
# Build loop
# ---------------------------------------------------------------------------

JOBS_ARGS=()
if [ -n "$JOBS_ARG" ]; then
    case "$JOBS_ARG" in ''|*[!0-9]*) die "--jobs must be a number (got '$JOBS_ARG')" ;; esac
    export JOBS="$JOBS_ARG" # keep the banner honest; children get it via --jobs too
    JOBS_ARGS=( --jobs "$JOBS_ARG" )
fi

build_command_for() {
    local target="$1"
    case "$target" in
        linux-x64)
            BUILD_CMD=( "$SCRIPT_DIR/build-linux.sh" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} --arch x86_64 )
            ;;
        windows-x64)
            BUILD_CMD=( "$SCRIPT_DIR/build-windows.sh" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} )
            ;;
        android-*)
            BUILD_CMD=( "$SCRIPT_DIR/build-android.sh" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} \
                --abis "${target#android-}" --api "$API" )
            ;;
        web)
            BUILD_CMD=( "$SCRIPT_DIR/build-web.sh" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} )
            ;;
        *) die "internal error: no build command for '$target'" ;;
    esac
    if [ "$CLEAN" = "1" ]; then
        BUILD_CMD+=( --clean )
    fi
}

quote_cmd() {
    local out="" arg
    for arg in "$@"; do
        out="$out$(printf '%q' "$arg") "
    done
    printf '%s' "${out% }"
}

DONE_TARGETS=()
FAILED_TARGET=""
TOTAL_START=$(date +%s)

for target in "${CHOSEN[@]}"; do
    build_command_for "$target"
    ffmpeg_banner "$target"
    start=$(date +%s)

    if [ "$DRY_RUN" = "1" ]; then
        log "would run: $(quote_cmd "${BUILD_CMD[@]}")"
    else
        if ! "${BUILD_CMD[@]}"; then
            FAILED_TARGET="$target"
            break
        fi
    fi

    if [ "$DO_INSTALL" = "1" ]; then
        if [ "$DRY_RUN" = "1" ]; then
            log "would run: $(quote_cmd "$SCRIPT_DIR/install-to-app.sh" "$target")"
        else
            "$SCRIPT_DIR/install-to-app.sh" "$target"
        fi
    fi

    DONE_TARGETS+=( "$target" )
    log "$target finished in $(ffmpeg_elapsed "$start")"
done

printf '\n[ffmpeg] summary (%s total)\n' "$(ffmpeg_elapsed "$TOTAL_START")"
for target in ${DONE_TARGETS[@]+"${DONE_TARGETS[@]}"}; do
    printf '  %-22s %s\n' "$target" "ok"
done
if [ -n "$FAILED_TARGET" ]; then
    printf '  %-22s %s\n' "$FAILED_TARGET" "FAILED"
    die "build failed for $FAILED_TARGET"
fi

if [ "$DO_INSTALL" = "1" ]; then
    log "done: ${#DONE_TARGETS[@]} target(s) built and installed"
else
    log "done: ${#DONE_TARGETS[@]} target(s) built (not installed)"
fi
