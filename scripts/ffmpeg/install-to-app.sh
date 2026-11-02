#!/usr/bin/env bash
# =============================================================================
# install-to-app.sh — copy built artifacts into the Flutter app trees
# (contract §8). Only binary artifacts are placed there; no CMake/Gradle/
# manifest files are touched.
#
#   scripts/ffmpeg/install-to-app.sh [--dry-run] <target>...
#
#   target: linux-x64 | windows-x64 | android-arm64-v8a | android-armeabi-v7a
#           | android-x86_64 | web | macos | linux | windows | android | all
#
# Destination mapping (contract §8):
#   linux-x64             -> linux/ffmpeg/ffmpeg
#   windows-x64           -> windows/ffmpeg/ffmpeg.exe
#   android-<abi>         -> android/app/src/main/jniLibs/<abi>/libffmpeg_exe.so
#   web                   -> web/ffmpeg/ffmpeg.js + ffmpeg.wasm
#   macos                 -> macos/ffmpeg/ffmpeg (copied into Contents/Frameworks
#                            by the Runner build phase, see macos/README.md)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

DRY_RUN=0
TARGETS=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] <target>...

Copy build/ffmpeg/dist/<target>/ artifacts into the Flutter app trees
(contract §8). Targets: linux-x64, windows-x64, android-arm64-v8a,
android-armeabi-v7a, android-x86_64, web, macos, or the aliases linux, windows,
android (all three ABIs) and all.

Options:
      --dry-run     print what would be installed, copy nothing
  -h, --help        show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*)        die "unknown option '$1' (see --help)" ;;
        *)         TARGETS+=( "$1" ); shift ;;
    esac
done
[ "${#TARGETS[@]}" -gt 0 ] || { usage; die "no target given"; }

expand_targets() {
    local t
    for t in "$@"; do
        case "$t" in
            all)
                # web 暂时废弃（m05703）：不放进 all，但映射代码保留。
                printf '%s\n' linux-x64 windows-x64 \
                    android-arm64-v8a android-armeabi-v7a android-x86_64 macos ;;
            linux)      printf 'linux-x64\n' ;;
            windows)    printf 'windows-x64\n' ;;
            android)    printf '%s\n' android-arm64-v8a android-armeabi-v7a android-x86_64 ;;
            web)
                # 暂时废弃（m05703）：保留分支，报错信息比 "unknown target" 清楚。
                die "web 暂时废弃；如需重新启用请还原 install-to-app.sh 里的注释"
                ;;
            macos|linux-x64|windows-x64|android-*) printf '%s\n' "$t" ;;
            *) die "unknown target '$t' (expected linux-x64, windows-x64, android-<abi>, web, macos, all)" ;;
        esac
    done
}
# Expand in the main shell first: die() inside a process substitution only ends
# the subshell, and the caller then reports the confusing "0 artifacts".
for t in "${TARGETS[@]}"; do
    case "$t" in
        web) die "web 暂时废弃；如需重新启用请还原 install-to-app.sh 里的注释" ;;
    esac
done
mapfile -t TARGETS < <(expand_targets "${TARGETS[@]}")

# install_one <src> <dst> <mode> <label>
install_one() {
    local src="$1" dst="$2" mode="$3" label="$4"
    [ -f "$src" ] || die "missing artifact for $label: $src (build it first: scripts/ffmpeg/build-*.sh)"
    if [ "$DRY_RUN" = "1" ]; then
        printf '[ffmpeg] would install %s -> %s (mode %s, %s bytes)\n' \
            "$src" "$dst" "$mode" "$(wc -c < "$src" | tr -d ' ')"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    install -m "$mode" "$src" "$dst"
    printf '[ffmpeg] installed %s -> %s (mode %s, %s bytes)\n' \
        "$src" "$dst" "$mode" "$(wc -c < "$dst" | tr -d ' ')"
}

installed=0
for target in "${TARGETS[@]}"; do
    ffmpeg_check_target_name "$target"
    dist="$(ffmpeg_distdir "$target")"
    [ -d "$dist" ] || die "no build output for '$target' at $dist (run scripts/ffmpeg/build-${target%%-*}.sh first)"
    [ -s "$dist/version.txt" ] || die "missing non-empty $dist/version.txt (contract §5/§9); rebuild $target"

    case "$target" in
        linux-x64)
            install_one "$dist/ffmpeg" "$REPO_ROOT/linux/ffmpeg/ffmpeg" 0755 "$target"
            installed=$((installed + 1))
            ;;
        windows-x64)
            install_one "$dist/ffmpeg.exe" "$REPO_ROOT/windows/ffmpeg/ffmpeg.exe" 0755 "$target"
            installed=$((installed + 1))
            ;;
        android-arm64-v8a|android-armeabi-v7a|android-x86_64)
            abi="${target#android-}"
            install_one "$dist/libffmpeg_exe.so" \
                "$REPO_ROOT/android/app/src/main/jniLibs/$abi/libffmpeg_exe.so" 0755 "$target"
            installed=$((installed + 1))
            ;;
        # web 暂时废弃（m05703）：安装逻辑原样保留，目标入口已被 die 拦住。
        web)
            install_one "$dist/ffmpeg.js"         "$REPO_ROOT/web/ffmpeg/ffmpeg.js"         0644 "$target"
            install_one "$dist/ffmpeg.wasm"       "$REPO_ROOT/web/ffmpeg/ffmpeg.wasm"       0644 "$target"
            installed=$((installed + 2))
            ;;
        macos)
            # The repo keeps the universal binary; the Runner build phase copies
            # it to Contents/Frameworks/ffmpeg and re-signs it there. Signing
            # happens at build time, not here, because the copy Xcode makes is a
            # different file and would lose the signature.
            install_one "$dist/ffmpeg" "$REPO_ROOT/macos/ffmpeg/ffmpeg" 0755 "$target"
            installed=$((installed + 1))
            ;;
    esac
    printf '[ffmpeg]   version.txt: %s\n' "$(head -n1 "$dist/version.txt")"
done

if [ "$DRY_RUN" = "1" ]; then
    log "dry run: $installed artifact(s) would be installed"
else
    log "$installed artifact(s) installed into the app tree"
fi
