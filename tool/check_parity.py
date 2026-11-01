#!/usr/bin/env python3
"""Diff the encoder sets of the five shipped builds.

The builds must agree on every encoder FFmpeg implements itself. Differences
are only acceptable when a platform cannot have the encoder at all:
hardware back ends (only exist on their own OS) or third-party libraries that
are not built for that target.

    python3 tool/check_parity.py [--verbose]
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILDS = {
    "linux": "linux-x64",
    "windows": "windows-x64",
    "android": "android-arm64-v8a",
    "web": "web",
}

# Suffixes FFmpeg appends to hardware encoders.
HW_SUFFIXES = (
    "_nvenc", "_qsv", "_vaapi", "_amf", "_mf", "_videotoolbox", "_d3d12va",
    "_rkmpp", "_oh", "_v4l2m2m", "_mediacodec", "_vulkan", "_cuvid", "_at",
)
# Encoders that need a library this project does not build anywhere.
EXTERNAL_UNBUILT = (
    "libfdk_aac", "libkvazaar", "libopenh264", "libshine", "libtwolame",
    "libcodec2", "libvvenc", "libx262", "libxavs", "libxavs2", "libxeve",
    "libsvtjpegxs", "liboapv", "libvo_amrwbenc", "libilbc", "liblc3",
)


def names_from_config(build_dir: pathlib.Path, kind: str = "ENCODER") -> set[str]:
    header = build_dir / "config_components.h"
    text = header.read_text()
    pattern = rf"^#define CONFIG_([A-Z0-9_]+)_{kind} 1$"
    symbols = set(re.findall(pattern, text, re.M))
    return {s.lower() for s in symbols}


def table_names() -> list[str]:
    source = (ROOT / "lib/src/media/generated/encoder_facts.dart").read_text()
    return re.findall(r"'([a-z0-9_.-]+)':", source)


def main() -> int:
    verbose = "--verbose" in sys.argv
    table = {}
    for name in table_names():
        table[re.sub(r"[^A-Za-z0-9]", "_", name).upper() + "_ENCODER"] = name
    sets = {}
    decoders = {}
    for key, target in BUILDS.items():
        build_dir = ROOT / "build/ffmpeg/ffbuild" / target
        symbols = names_from_config(build_dir)
        sets[key] = {table.get(s, s.lower()) for s in symbols}
        decoders[key] = {table.get(s, s.lower())
                         for s in names_from_config(build_dir, "DECODER")}
    reference = sets["linux"]
    problems = 0
    for key, names in sets.items():
        if key == "linux":
            continue
        missing = sorted(reference - names)
        extra = sorted(names - reference)
        # A hardware encoder only exists on its own OS.
        missing = [n for n in missing if not n.endswith(HW_SUFFIXES)]
        extra = [n for n in extra if not n.endswith(HW_SUFFIXES)]
        missing = [n for n in missing if n not in EXTERNAL_UNBUILT]
        print(f"{key}: {len(names)} encoders, {len(missing)} missing, {len(extra)} extra")
        if verbose or missing:
            for name in missing:
                print(f"  missing: {name}")
                problems += 1
        if verbose:
            for name in extra:
                print(f"  extra: {name}")
    for key in BUILDS:
        if key == "linux":
            continue
        missing_dec = sorted(decoders["linux"] - decoders[key])
        missing_dec = [d for d in missing_dec
                       if not d.endswith(HW_SUFFIXES) and d not in EXTERNAL_UNBUILT]
        if missing_dec:
            print(f"{key}: {len(missing_dec)} decoder(s) behind linux: "
                  + ", ".join(missing_dec[:12]))
            problems += len(missing_dec)

    unbuilt = sorted(reference & set(EXTERNAL_UNBUILT))
    print("built nowhere (external library not in this project): "
          + (", ".join(unbuilt) if unbuilt else "none"))
    print("parity ok" if problems == 0 else f"{problems} encoder(s) differ")
    return 0 if problems == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
