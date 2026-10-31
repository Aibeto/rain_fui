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
"""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import sys

ISOLATION_HEADERS = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    # Let the wasm core spawn its pthread workers from the same origin.
    "Cross-Origin-Resource-Policy": "same-origin",
}


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
    httpd = http.server.ThreadingHTTPServer(
        (args.host, args.port), functools.partial(Handler, directory=root)
    )
    mode = "isolated" if Handler.isolation else "NOT isolated (FFmpeg will refuse to start)"
    sys.stderr.write("serving %s on http://%s:%d (%s)\n" % (root, args.host, args.port, mode))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\nstopped\n")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
