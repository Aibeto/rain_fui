#!/usr/bin/env python3
"""Serve the Flutter web build with the headers FFmpeg's wasm core needs.

FFmpeg's web build is compiled with pthreads (see docs/build-contract.md §7),
so the page must be *cross-origin isolated* before `SharedArrayBuffer` exists:
a document served without COOP/COEP cannot start the wasm module at all.

`flutter run -d chrome` does not send those headers, so use this server for any
manual check of the web target:

    flutter build web --release
    python3 tool/serve_web.py            # http://127.0.0.1:8080
    python3 tool/serve_web.py --dir build/web --port 9000
    python3 tool/serve_web.py --no-isolation   # see the graceful failure path

`--no-isolation` deliberately omits the headers: the app must still load and
report "cross-origin isolation required" instead of hanging on a broken wasm.

`--smoke` additionally serves an end-to-end check at /__smoke.html that runs the
bridge (`init()` + one real `-f lavfi` mpeg4/aac transcode) and prints
`SMOKE_OK` when the wasm core really works. It is a normal page, so a headless
browser can drive it:

    python3 tool/serve_web.py --smoke &
    chromium --headless=new --no-sandbox --dump-dom \
        http://127.0.0.1:8080/__smoke.html | grep SMOKE_OK

The page holds its own `load` event until the run finishes, so `--dump-dom`
waits for the result instead of racing the wasm compile.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import sys
import threading

ISOLATION_HEADERS = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    # Let the wasm core spawn its pthread workers from the same origin.
    "Cross-Origin-Resource-Policy": "same-origin",
}


SMOKE_HTML = """<!doctype html>
<meta charset="utf-8">
<title>rain_fui ffmpeg web smoke</title>
<pre id="out">running</pre>
<script src="ffmpeg/ffmpeg_bridge.js"></script>
<script>
(function () {
  var out = document.getElementById('out');
  var lines = [];
  function log(text) {
    lines.push(text);
    out.textContent = lines.join(String.fromCharCode(10));
  }
  function finish() {
    try { fetch('/__smoke/done'); } catch (error) {}
  }
  (async function () {
    try {
      if (!window.rainFfmpeg) throw new Error('ffmpeg/ffmpeg_bridge.js did not load');
      var init = await window.rainFfmpeg.init();
      log('INIT ' + JSON.stringify(init));
      if (!init.ok) throw new Error('init failed: ' + init.error);
      var result = await window.rainFfmpeg.run([
        '-hide_banner', '-nostdin', '-nostats', '-progress', 'pipe:1',
        '-f', 'lavfi', '-i', 'testsrc2=duration=1:size=320x240:rate=25',
        '-c:v', 'mpeg4', '-c:a', 'aac', '-y', '/tmp/rain_fui_smoke.mp4'
      ], function (line) { log('LINE ' + line); });
      log('RUN ' + JSON.stringify(result));
      var ok = result.exitCode === 0 &&
        /Output #0/.test(result.stderr || '') &&
        /progress=end/.test(result.stdout || '');
      log(ok ? 'SMOKE_OK' : 'SMOKE_FAIL');
    } catch (error) {
      log('SMOKE_ERROR ' + (error && (error.stack || error.message || error)));
      log('SMOKE_FAIL');
    } finally {
      finish();
    }
  })();
})();
</script>
<script src="__smoke/hold.js"></script>
"""

SMOKE_HOLD_JS = """// Holds the document's load event until the smoke test reports back.
(function () {
  var started = Date.now();
  var script = document.createElement('script');
  script.src = '__smoke/wait.js?' + Date.now();
  document.head.appendChild(script);
})();
"""


SMOKE_DONE = threading.Event()


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".symbols": "text/plain",
        ".map": "application/json",
    }

    isolation = True
    smoke = False

    def _send(self, status: int, body: bytes, content_type: str = "text/plain") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: D102 - inherited contract
        if self.smoke:
            path = self.path.split("?", 1)[0]
            if path == "/__smoke.html":
                SMOKE_DONE.clear()
                self._send(200, SMOKE_HTML.encode(), "text/html; charset=utf-8")
                return
            if path == "/__smoke/hold.js":
                # Blocks until the smoke page posts /__smoke/done, so the
                # browser's load event (and --dump-dom) waits for the result.
                SMOKE_DONE.wait(300)
                self._send(200, b"/*smoke finished*/", "text/javascript")
                return
            if path == "/__smoke/wait.js":
                self._send(200, b"/*noop*/", "text/javascript")
                return
            if path == "/__smoke/done":
                SMOKE_DONE.set()
                self._send(204, b"")
                return
        super().do_GET()

    def do_POST(self) -> None:  # noqa: D102 - inherited contract
        if self.smoke and self.path.split("?", 1)[0] == "/__smoke/done":
            SMOKE_DONE.set()
            self._send(204, b"")
            return
        self._send(404, b"not found")

    def end_headers(self) -> None:  # noqa: D102 - inherited contract
        if self.isolation:
            for name, value in ISOLATION_HEADERS.items():
                self.send_header(name, value)
        # Never cache during manual testing; a stale ffmpeg.wasm is confusing.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt: str, *args: object) -> None:  # noqa: D102
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main() -> int:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--dir",
        default=os.path.join(here, "build", "web"),
        help="directory to serve (default: <repo>/build/web)",
    )
    parser.add_argument("--port", type=int, default=8080, help="port (default: 8080)")
    parser.add_argument("--host", default="127.0.0.1", help="bind address")
    parser.add_argument(
        "--no-isolation",
        action="store_true",
        help="omit COOP/COEP to exercise the graceful 'needs isolation' path",
    )
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="also serve /__smoke.html (real wasm transcode check)",
    )
    args = parser.parse_args()

    root = os.path.abspath(args.dir)
    if not os.path.isdir(root):
        sys.stderr.write(
            "error: %s does not exist - run `flutter build web --release` first\n" % root
        )
        return 1
    index = os.path.join(root, "index.html")
    if not os.path.isfile(index):
        sys.stderr.write("error: %s has no index.html\n" % root)
        return 1

    Handler.isolation = not args.no_isolation
    Handler.smoke = args.smoke
    httpd = http.server.ThreadingHTTPServer(
        (args.host, args.port), functools.partial(Handler, directory=root)
    )
    mode = "isolated" if Handler.isolation else "NOT isolated (FFmpeg will refuse to start)"
    smoke = " + /__smoke.html" if args.smoke else ""
    sys.stderr.write(
        "serving %s on http://%s:%d (%s%s)\n" % (root, args.host, args.port, mode, smoke)
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\nstopped\n")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
