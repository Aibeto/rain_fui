#!/usr/bin/env python3
"""Assert that a build really contains the encoders CI is supposed to produce.

A green FFmpeg build proves nothing about its contents: without
FFMPEG_EXTERNAL_LIBS=1 the binary compiles fine and simply has no libx264,
libx265, libaom-av1 or MediaCodec. This script fails the CI leg instead of
shipping a quietly poorer build.

    python3 tool/check_expected_encoders.py --target android-arm64-v8a \
        --expect libx264,libx265,libaom-av1,h264_mediacodec

The encoder list is read from `build/ffmpeg/ffbuild/<target>/config_components.h`
(`CONFIG_<SYMBOL>_ENCODER 1`), which every build writes. When that header is
absent the script falls back to running the built binary with `-encoders`,
which only works for a target the host can execute (linux-x64 in practice).

`--forbid` is the inverse check: it fails when any listed encoder is present,
e.g. a Linux-only back end that must not appear in the Windows build.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FFBUILD = ROOT / "build/ffmpeg/ffbuild"
DIST = ROOT / "build/ffmpeg/dist"

# name -> artifact the dist directory holds for that target
BINARIES = {
    "linux-x64": "ffmpeg",
    "windows-x64": "ffmpeg.exe",
    "macos": "ffmpeg",
    "web": "ffmpeg.js",
}

# A universal dist target is built from two trees; the arm64 one carries the
# configure result for both (same feature set, different -arch).
CONFIG_DIRS = {
    "macos": "macos-arm64",
}

CONFIG_LINE = re.compile(r"^#define\s+CONFIG_([A-Z0-9_]+)_ENCODER\s+1\s*$")
LISTED = re.compile(r"^\s*([VAS])[.A-Z]{5}\s+(\S+)\s*=")

# Encoder name -> CONFIG_<symbol>_ENCODER, only where the two differ. libvpx is
# the VP8 encoder in the CLI but the symbol carries the version, so a plain
# upper-case mapping of the name would look for a symbol FFmpeg never writes.
SYMBOL_ALIASES = {
    "libvpx": "LIBVPX_VP8",
    "libvpx-vp9": "LIBVPX_VP9",
    "libaom-av1": "LIBAOM_AV1",
    "libsvtav1": "LIBSVTAV1",
    "libmp3lame": "LIBMP3LAME",
}


def symbol_for(name: str) -> str:
    """libaom-av1 -> LIBAOM_AV1, h264_mediacodec -> H264_MEDIACODEC."""
    if name in SYMBOL_ALIASES:
        return SYMBOL_ALIASES[name]
    return re.sub(r"[^A-Za-z0-9]", "_", name).upper()


def from_config(target: str) -> set[str] | None:
    header = FFBUILD / CONFIG_DIRS.get(target, target) / "config_components.h"
    if not header.is_file():
        return None
    symbols = set()
    for line in header.read_text(encoding="utf-8", errors="replace").splitlines():
        match = CONFIG_LINE.match(line)
        if match:
            symbols.add(match.group(1))
    return symbols


def from_binary(target: str) -> set[str] | None:
    name = BINARIES.get(target)
    if not name:
        return None
    binary = DIST / target / name
    if not binary.is_file():
        return None
    try:
        out = subprocess.run(
            [str(binary), "-hide_banner", "-encoders"],
            capture_output=True, text=True, timeout=120,
        )
    except OSError as error:  # not executable on this host
        print(f"cannot run {binary}: {error}")
        return None
    if out.returncode != 0:
        return None
    names = set()
    for line in out.stdout.splitlines():
        match = LISTED.match(line)
        if match:
            names.add(match.group(2))
    return names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True,
                        help="dist target name, e.g. linux-x64 or android-x86_64")
    parser.add_argument("--expect", default="",
                        help="comma separated encoder names that must exist")
    parser.add_argument("--forbid", default="",
                        help="comma separated encoder names that must not exist")
    args = parser.parse_args()

    expect = [n for n in args.expect.split(",") if n]
    forbid = [n for n in args.forbid.split(",") if n]

    symbols = from_config(args.target)
    if symbols is not None:
        source = f"ffbuild/{CONFIG_DIRS.get(args.target, args.target)}/config_components.h"
        missing = [n for n in expect if symbol_for(n) not in symbols]
    else:
        names = from_binary(args.target)
        if names is None:
            cfg = CONFIG_DIRS.get(args.target, args.target)
            print(f"no encoder list for {args.target}: "
                  f"neither {FFBUILD / cfg} nor a runnable binary")
            return 1
        source = f"dist/{args.target} -encoders"
        present = set(names)
        missing = [n for n in expect if n not in names]
        symbols = set()

    print(f"{args.target}: encoder list from {source}")
    if expect:
        print(f"  expected present: {', '.join(expect)}")
    if missing:
        print(f"  MISSING: {', '.join(missing)}")
        print("  hint: rebuild with FFMPEG_EXTERNAL_LIBS=1 and a populated "
              "dependency prefix (scripts/ffmpeg/build-deps.sh)")
        return 1

    if forbid:
        if symbols:
            banned = [n for n in forbid if symbol_for(n) in symbols]
        else:
            banned = [n for n in forbid if n in present]
        if banned:
            print(f"  MUST NOT BE PRESENT: {', '.join(banned)}")
            return 1

    print(f"  {len(expect)} expected encoder(s) present"
          + (f", {len(forbid)} forbidden absent" if forbid else "")
          + " — ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
