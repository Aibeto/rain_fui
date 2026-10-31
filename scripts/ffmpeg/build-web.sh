#!/usr/bin/env bash
# =============================================================================
# build-web.sh — WebAssembly FFmpeg (contract target: web).
#
#   scripts/ffmpeg/build-web.sh [--jobs N] [--clean] [--no-smoke]
#
# FFmpeg 9's CLI scheduler (fftools/ffmpeg_sched.c) creates one pthread per
# demux/decode/filter/encode/mux task, so the web build is THREADED: FFmpeg is
# configured with --enable-pthreads, the pthread bootstrap is inlined in
# ffmpeg.js (Emscripten 6 no longer emits a separate worker script), and the
# page must be cross-origin isolated (COOP
# same-origin + COEP require-corp) so SharedArrayBuffer is available. The
# ffmpeg program is still configured with --disable-programs and its CLI
# frontend (fftools/ffmpeg.c + friends) is linked manually, because the
# target-os=none/emscripten environment does not run the normal program link.
# The ABI is contract §7 (createFFmpegCore / MODULARIZE / INVOKE_RUN=0 /
# FS + callMain exported).
#
# Artifacts (§5): build/ffmpeg/dist/web/ffmpeg.js + ffmpeg.wasm + version.txt
# (no separate pthread worker script: Emscripten 6 re-uses this same script
#  URL, i.e. web/ffmpeg/ffmpeg_worker.js, for its pthread workers -- see
#  web/ffmpeg/ffmpeg_worker.js, which special-cases self.name === 'em-pthread'.)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/ffmpeg/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET="web"
CLEAN=0
SMOKE=1

usage() {
    cat <<EOF
Usage: $(basename "$0") [--jobs N] [--clean] [--no-smoke]

Build the Emscripten/WASM FFmpeg CLI (contract target: $TARGET).
Requires an activated emsdk (emcc/em++/emar/emranlib/emnm on PATH).

Options:
      --jobs N      parallel compile jobs (default: $(ffmpeg_default_jobs))
      --clean       delete build/ffmpeg/ffbuild/web before configuring
      --no-smoke    skip the Node callMain(['-version']) smoke test
EOF
    ffmpeg_usage_common
    cat <<EOF
Environment:
      EMSDK              emsdk root (default: \$HOME/emsdk)
      FFMPEG_LTO=0       disable LTO (emcc LTO is the most fragile target)
      JOBS
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --jobs)     JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)   JOBS="${1#*=}"; shift ;;
        --clean)    CLEAN=1; shift ;;
        --no-smoke) SMOKE=0; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "unknown argument '$1' (see --help)" ;;
    esac
done

ffmpeg_validate_jobs
require_ffmpeg_src

EMSDK="${EMSDK:-$HOME/emsdk}"
if ! command -v emcc >/dev/null 2>&1; then
    if [ -f "$EMSDK/emsdk_env.sh" ]; then
        log "activating emsdk: $EMSDK/emsdk_env.sh"
        # emsdk_env.sh is not nounset-safe; protect the caller's shell options.
        set +u
        # shellcheck disable=SC1090
        source "$EMSDK/emsdk_env.sh" >/dev/null 2>&1 || die "failed to source $EMSDK/emsdk_env.sh"
        set -u
    else
        die "emcc not found. Install emsdk (https://emscripten.org) or source \$EMSDK/emsdk_env.sh first"
    fi
fi
for tool in emcc em++ emar emranlib emnm; do
    require_cmd "$tool" "emsdk is not fully activated (missing $tool)"
done
log "emcc: $(command -v emcc) ($(emcc --version 2>/dev/null | head -n1))"

builddir="$(ffmpeg_builddir "$TARGET")"
distdir="$(ffmpeg_distdir "$TARGET")"
ffmpeg_check_target_name "$TARGET"
mkdir -p "$distdir"

ffmpeg_banner "$TARGET"

if [ "$CLEAN" = "1" ]; then
    ffmpeg_reset_builddir "$builddir"
fi

# --- configure the static libraries -----------------------------------------
args=( "${FFMPEG_BASE_FLAGS[@]}" )
args+=(
    --prefix="$builddir/prefix"
    --target-os=none
    --arch=x86_32
    --enable-cross-compile
    --cc=emcc
    --cxx=em++
    --ar=emar
    --ranlib=emranlib
    --nm=emnm
    --disable-asm
    --disable-x86asm
    --disable-inline-asm
    --disable-programs
    --disable-network
    --disable-runtime-cpudetect
    --enable-pthreads
    --disable-w32threads
    --disable-os2threads
    --disable-stripping
    --extra-cflags="-O3 -fPIC -pthread"
    --extra-cxxflags="-O3 -fPIC -pthread"
    --extra-ldflags="-pthread"
)

lto_cfg="$(ffmpeg_lto_configure_flags emcc)"
if [ -n "$lto_cfg" ]; then
    args+=( "$lto_cfg" )
fi

start="$(date +%s)"
ffmpeg_configure "$builddir" "${args[@]}"
ffmpeg_assert_license "$builddir"

# --- libraries ---------------------------------------------------------------
ffmpeg_make "$builddir"

# --- CLI frontend objects (program was disabled, so build them explicitly) ---
fftools_objs=(
    fftools/ffmpeg.o
    fftools/cmdutils.o
    fftools/opt_common.o
    fftools/ffmpeg_dec.o
    fftools/ffmpeg_demux.o
    fftools/ffmpeg_enc.o
    fftools/ffmpeg_filter.o
    fftools/ffmpeg_hw.o
    fftools/ffmpeg_mux.o
    fftools/ffmpeg_mux_init.o
    fftools/ffmpeg_opt.o
    fftools/ffmpeg_sched.o
    fftools/graph/graphprint.o
    fftools/sync_queue.o
    fftools/thread_queue.o
    fftools/textformat/avtextformat.o
    fftools/textformat/tf_compact.o
    fftools/textformat/tf_default.o
    fftools/textformat/tf_flat.o
    fftools/textformat/tf_ini.o
    fftools/textformat/tf_json.o
    fftools/textformat/tf_mermaid.o
    fftools/textformat/tf_xml.o
    fftools/textformat/tw_avio.o
    fftools/textformat/tw_buffer.o
    fftools/textformat/tw_stdout.o
    fftools/resources/resman.o
    fftools/resources/graph.html.o
    fftools/resources/graph.css.o
)
mkdir -p "$builddir/fftools/textformat" "$builddir/fftools/resources" "$builddir/fftools/graph"
log "compiling the ffmpeg CLI frontend (${#fftools_objs[@]} objects)"
# The fftools objects embed config.h decisions (e.g. CONFIG_AVDEVICE), and the
# build system does not track that dependency, so drop them after every
# configure to keep them in sync with the current feature set.
rm -f "${fftools_objs[@]/#/$builddir/}"
ffmpeg_make "$builddir" "${fftools_objs[@]}"

# --- link the CLI as a MODULARIZE'd WASM factory (contract §7) --------------
link_flags=(
    -O3 -fPIC -pthread
    -I"$builddir" -I"$FFMPEG_SRC" -DHAVE_AV_CONFIG_H
    -Wl,--start-group
    -L"$builddir/libavdevice" -L"$builddir/libavfilter" -L"$builddir/libavformat" -L"$builddir/libavcodec"
    -L"$builddir/libswresample" -L"$builddir/libswscale" -L"$builddir/libavutil"
    -lavdevice -lavfilter -lavformat -lavcodec -lswresample -lswscale -lavutil
    -Wl,--end-group
    -lm
)
if [ "${FFMPEG_LTO}" != "0" ]; then
    link_flags+=( -flto=full )
fi
link_flags+=(
    -sMODULARIZE=1
    -sEXPORT_NAME=createFFmpegCore
    -sINVOKE_RUN=0
    -sENVIRONMENT=web,worker
    -sALLOW_MEMORY_GROWTH=1
    -sINITIAL_MEMORY=67108864
    -sMAXIMUM_MEMORY=2147483648
    -sPTHREAD_POOL_SIZE=8
    -sPTHREAD_POOL_SIZE_STRICT=0
    -sPTHREAD_POOL_DELAY_LOAD=1
    # FFmpeg's CLI blocks its main thread while the scheduler waits on worker
    # threads. A blocking main thread cannot service Emscripten's proxied calls
    # (thread startup, heap growth), which deadlocks the run, so main() has to
    # live on a pthread while the hosting worker stays free.
    -sPROXY_TO_PTHREAD=1
    -sFORCE_FILESYSTEM=1
    -sEXPORTED_FUNCTIONS=_main,_malloc,_free
    -sEXPORTED_RUNTIME_METHODS=FS,callMain,ccall,cwrap
    -sSTACK_SIZE=5242880
    # The caller needs to know when main() finished: with PROXY_TO_PTHREAD the
    # exit status arrives through Module.onExit, which Emscripten only invokes
    # when the runtime is actually torn down.
    -sEXIT_RUNTIME=1
    -sASSERTIONS=0
    -o "$distdir/ffmpeg.js"
)

log "linking $distdir/ffmpeg.js"
mkdir -p "$builddir/obj"
(
    cd "$builddir"
    emcc "${link_flags[@]}" "${fftools_objs[@]}"
)
# Emscripten >= 4 inlines the pthread bootstrap into ffmpeg.js (it creates
# the thread workers from `self.location.href`), so no separate .worker.js is
# emitted any more; the two files below are the whole contract.
for artifact in ffmpeg.js ffmpeg.wasm; do
    [ -s "$distdir/$artifact" ] || die "emcc did not produce $distdir/$artifact"
done

# --- smoke tests: instantiate the factory, then exercise real CLI paths ----
first=""
smoke_fail=0
if [ "$SMOKE" = "1" ] && command -v node >/dev/null 2>&1; then
    smoke="$builddir/smoke-test.cjs"
    cat > "$smoke" <<'SMOKE_EOF'
const fs = require('fs');
const path = require('path');
const dir = process.env.WEB_DIST;
const smokeOut = process.env.WEB_SMOKE_OUT;
const args = JSON.parse(process.env.WEB_SMOKE_ARGS || '["-version"]');
// The artifact is compiled with -sENVIRONMENT=web,worker (contract §7); give
// Node the minimal window/document surface the web environment probe expects,
// and feed the wasm through instantiateWasm so no fetch() is attempted.
global.window = global;
global.document = { currentScript: { src: 'file://' + path.join(dir, 'ffmpeg.js') } };
const wasm = fs.readFileSync(path.join(dir, 'ffmpeg.wasm'));
const createFFmpegCore = require(path.join(dir, 'ffmpeg.js'));
const out = [];
const err = [];
createFFmpegCore({
  instantiateWasm(imports, successCallback) {
    WebAssembly.instantiate(wasm, imports).then((r) => successCallback(r.instance));
    return {};
  },
  print: (s) => out.push(s),
  printErr: (s) => err.push(s),
}).then((m) => {
  let rc = 1;
  try {
    rc = m.callMain(args);
  } catch (e) {
    err.push('callMain threw: ' + e);
  }
  fs.writeFileSync(smokeOut, out.join('\n') + '\n' + err.join('\n'));
  process.exit(typeof rc === 'number' ? rc : 3);
}).catch((e) => {
  console.error('smoke test failed:', e);
  process.exit(2);
});
SMOKE_EOF
    web_smoke() { # $1 = JSON argv, $2 = output file
        ( cd "$distdir" && WEB_DIST="$distdir" WEB_SMOKE_OUT="$builddir/$2" \
              WEB_SMOKE_ARGS="$1" node "$smoke" )
    }

    if web_smoke '["-version"]' smoke-version.out &&
       grep -qE 'ffmpeg version n?9\.0\.2' "$builddir/smoke-version.out"; then
        first="$(grep -m1 '^ffmpeg version ' "$builddir/smoke-version.out" || true)"
        log "node smoke test: -version OK"
    else
        warn "node smoke test failed: -version (see $builddir/smoke-version.out)"
        smoke_fail=1
    fi

    # Real pipeline: lavfi source -> null muxer. Catches builds that start but
    # have no functional input/encoder/muxer path (e.g. avdevice missing).
    if web_smoke '["-hide_banner","-f","lavfi","-i","testsrc2=duration=0.2:size=64x64:rate=5","-f","null","-"]' smoke-lavfi.out; then
        log "node smoke test: lavfi -> null OK"
    else
        warn "node smoke test failed: lavfi -> null (see $builddir/smoke-lavfi.out)"
        smoke_fail=1
    fi

    if [ "$smoke_fail" = "1" ] && [ "${FFMPEG_WEB_STRICT_SMOKE:-0}" = "1" ]; then
        die "web smoke tests failed (FFMPEG_WEB_STRICT_SMOKE=1)"
    fi
else
    [ "$SMOKE" = "1" ] && warn "node not found — skipping web smoke tests"
fi

if [ -n "$first" ]; then
    printf '%s\n' "$first" > "$distdir/version.txt"
else
    printf 'ffmpeg version %s (emscripten wasm build)\n' "$(ffmpeg_tag)" > "$distdir/version.txt"
fi

printf '\n[ffmpeg] %s: artifacts\n' "$TARGET"
ls -l "$distdir"
if command -v file >/dev/null 2>&1; then
    file "$distdir/ffmpeg.js" "$distdir/ffmpeg.wasm" || true
fi
[ -n "$first" ] && printf '  -version first line: %s\n' "$first"
log "$TARGET build complete in $(ffmpeg_elapsed "$start")"
