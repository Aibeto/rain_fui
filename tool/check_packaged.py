#!/usr/bin/env python3
"""Fail when the app trees still carry an older FFmpeg than build/ffmpeg/dist.

`scripts/ffmpeg/install-to-app.sh` is what puts artifacts where the Flutter
build picks them up. Forgetting it is invisible: the app runs, the probe
succeeds, and the encoder list is simply the old binary's. That is how the
Android build ended up offering the same (native-only) codecs as an old desktop
build.

    python3 tool/check_packaged.py [--only linux-x64]

--only keeps the check honest inside a CI leg that only built one target: the
pairs of the targets that were not built are not reported as stale.
"""

from __future__ import annotations

import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAIRS = {
    "build/ffmpeg/dist/linux-x64/ffmpeg": "linux/ffmpeg/ffmpeg",
    "build/ffmpeg/dist/windows-x64/ffmpeg.exe": "windows/ffmpeg/ffmpeg.exe",
    "build/ffmpeg/dist/android-arm64-v8a/libffmpeg_exe.so":
        "android/app/src/main/jniLibs/arm64-v8a/libffmpeg_exe.so",
    "build/ffmpeg/dist/android-armeabi-v7a/libffmpeg_exe.so":
        "android/app/src/main/jniLibs/armeabi-v7a/libffmpeg_exe.so",
    "build/ffmpeg/dist/android-x86_64/libffmpeg_exe.so":
        "android/app/src/main/jniLibs/x86_64/libffmpeg_exe.so",
    # web 暂时废弃（需求 m05703）：条目保留，重新启用时取消注释即可。
    # "build/ffmpeg/dist/web/ffmpeg.js": "web/ffmpeg/ffmpeg.js",
    # "build/ffmpeg/dist/web/ffmpeg.wasm": "web/ffmpeg/ffmpeg.wasm",
    "build/ffmpeg/dist/macos/ffmpeg": "macos/ffmpeg/ffmpeg",
}


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str]) -> int:
    only = ""
    if len(argv) == 2 and argv[0] == "--only":
        only = argv[1].strip("/")
    elif argv:
        print("usage: check_packaged.py [--only <dist-target>]")
        return 2

    stale = 0
    checked = 0
    for dist, app in PAIRS.items():
        if only and not dist.startswith(f"build/ffmpeg/dist/{only}/"):
            continue
        checked += 1
        source = ROOT / dist
        target = ROOT / app
        if not source.exists():
            print(f"missing build: {dist}")
            stale += 1
            continue
        if not target.exists():
            print(f"not installed: {app} (run install-to-app.sh)")
            stale += 1
            continue
        if digest(source) != digest(target):
            print(f"stale: {app} ({target.stat().st_size} B) "
                  f"!= {dist} ({source.stat().st_size} B)")
            stale += 1
    label = f"{only} " if only else ""
    if checked == 0:
        print(f"no packaged artifact for {only or 'any target'}")
        return 1
    print(f"packaged artifacts match ({label}{checked} file(s))"
          if stale == 0 else f"{stale} artifact(s) stale")
    return 0 if stale == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
