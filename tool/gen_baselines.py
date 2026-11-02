#!/usr/bin/env python3
"""Write the per-platform encoder baseline from each target's build config.

The runtime probe asks the binary for `-encoders`, which is the truth. When the
probe cannot run (web, or a sandbox that refuses to spawn a process) the app
falls back to a list baked in at build time. That list used to be the Linux
build's, which is wrong on Android: the Android build carries MediaCodec
encoders and the Linux one does not.

`config_components.h` in each build directory says exactly which encoders were
compiled in (`CONFIG_<SYMBOL>_ENCODER 1`), so the fallback list can be derived
without executing a foreign binary.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GENERATED = ROOT / "lib" / "src" / "media" / "generated" / "platform_baselines.dart"

# platform key -> build directory under build/ffmpeg/ffbuild
TARGETS = {
    "linux": "linux-x64",
    "windows": "windows-x64",
    "android": "android-arm64-v8a",
    "macos": "macos-arm64",
    "web": "web",
}


def encoder_names() -> list[str]:
    source = (ROOT / "lib/src/media/generated/encoder_facts.dart").read_text()
    return sorted(set(re.findall(r"'([a-z0-9_.-]+)':", source)))


def symbol(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "_", name).upper() + "_ENCODER"


def compiled(build_dir: pathlib.Path, names: list[str]) -> list[str]:
    header = build_dir / "config_components.h"
    if not header.exists():
        return []
    text = header.read_text()
    hit = []
    for name in names:
        if re.search(rf"^#define CONFIG_{symbol(name)} 1$", text, re.M):
            hit.append(name)
    return hit


def existing_blocks() -> dict[str, list[str]]:
    """Baselines already in the generated file, keyed by platform.

    A developer without an Android or macOS build tree must not silently delete
    that platform's baseline, so a platform whose build directory is missing
    keeps whatever the file already had.
    """
    if not GENERATED.exists():
        return {}
    text = GENERATED.read_text()
    out: dict[str, list[str]] = {}
    for match in re.finditer(
        r"  '([a-z]+)': <String>\{\n(.*?)\n  \},", text, re.S
    ):
        key, body = match.group(1), match.group(2)
        out[key] = re.findall(r"'([^']+)'", body)
    return out


def main() -> int:
    names = encoder_names()
    previous = existing_blocks()
    blocks = []
    for key, target in TARGETS.items():
        build_dir = ROOT / "build/ffmpeg/ffbuild" / target
        hits = compiled(build_dir, names)
        if not hits:
            kept = previous.get(key, [])
            if kept:
                print(f"keep {key}: no build tree at {build_dir}, reusing {len(kept)} encoders")
                hits = kept
            else:
                print(f"skip {key}: {build_dir} has no config_components.h")
                continue
        else:
            print(f"{key}: {len(hits)} encoders in {target}")
        body = "\n".join(f"    '{name}'," for name in hits)
        blocks.append(f"  '{key}': <String>{{\n{body}\n  }},")
    GENERATED.write_text(
        "// GENERATED FILE - do not edit by hand.\n"
        "// Regenerate with: python3 tool/gen_baselines.py\n"
        "\n"
        "/// Encoders each shipped build contains, keyed by platform.\n"
        "///\n"
        "/// Used only when the runtime probe cannot start the binary; a successful\n"
        "/// probe always wins.\n"
        "const Map<String, Set<String>> kPlatformBaselineEncoders = "
        "<String, Set<String>>{\n" + "\n".join(blocks) + "\n};\n"
    )
    print(f"wrote {GENERATED.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
