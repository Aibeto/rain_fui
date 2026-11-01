#!/usr/bin/env python3
"""Generate the encoder and container facts the encode form reads at runtime.

Inputs are the JSON files produced by tool/media_probe.py:

    tool/data/encoders-system.json    every encoder a full FFmpeg reports
    tool/data/encoders-bundled.json   what the shipped build reports
    tool/data/containers-system.json  which codec ids each muxer accepts

Outputs, all under lib/src/media/generated/:

    encoder_facts.dart    encoder -> codec id, and per-encoder pixel formats
    container_codecs.dart container -> accepted video / audio codec ids
    extra_encoders.dart   CodecSpec entries for encoders the hand-written table
                          does not cover (lib* and hardware variants)

The hand-written table keeps the friendly names and the per-encoder options;
this generator adds coverage, never opinion.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "tool" / "data"
OUT = ROOT / "lib" / "src" / "media" / "generated"

CURATED = re.compile(r"encoder: '([a-z0-9_]+)'")

# Encoders that exist for FFmpeg's own plumbing, not for a user to pick.
EXCLUDED_ENCODERS = {"wrapped_avframe", "anull", "comfortnoise"}

# Containers whose acceptance cannot be measured with a 64x64 one-frame probe:
# dv wants 720x576 at 25 fps, mxf wants a video stream next to the audio, and
# the Ogg family shares one muxer so `-f opus` happily accepts vorbis. The
# values below were measured by hand with the right frame size (see
# docs/ffmpeg-capabilities.md) or clamped to what the format means.
CONTAINER_OVERRIDES: dict[str, dict[str, list[str]]] = {
    "dv": {"video": ["dvvideo"], "audio": ["pcm_s16le"]},
    "mxf": {
        "video": ["dnxhd", "ffv1", "h264", "jpeg2000", "mpeg2video", "prores"],
        "audio": ["pcm_s16le", "pcm_s24le"],
    },
    "opus": {"video": [], "audio": ["opus"]},
    "flac": {"video": [], "audio": ["flac"]},
    "ac3": {"video": [], "audio": ["ac3"]},
    "adts": {"video": [], "audio": ["aac"]},
    "wv": {"video": [], "audio": ["wavpack"]},
}

HEADER = """// GENERATED FILE. Do not edit by hand.
//
// Produced by tool/gen_capabilities.py from the JSON files in tool/data/,
// which in turn come from running tool/media_probe.py against real FFmpeg
// binaries. Re-run the generator instead of editing this file.
"""


def load(name: str):
    return json.loads((DATA / name).read_text())


def quoted(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def curated_encoders() -> set[str]:
    text = (ROOT / "lib" / "src" / "media" / "capabilities_data.dart").read_text()
    return set(CURATED.findall(text))


def write_baseline(bundled: list[dict]) -> None:
    names = sorted({e["name"] for e in bundled})
    body = "\n".join(
        [
            HEADER,
            "",
            "/// Encoders the shipped FFmpeg build reports. Used when the runtime",
            "/// probe cannot run, so the pickers never offer an encoder the app",
            "/// cannot execute.",
            "const Set<String> kBaselineEncoderNames = <String>{",
            *[f"  {quoted(name)}," for name in names],
            "};",
            "",
        ]
    )
    (OUT / "baseline_encoders.dart").write_text(body)


def write_encoder_facts(encoders: list[dict]) -> None:
    codec_lines = []
    pixel_lines = []
    for encoder in sorted(encoders, key=lambda e: e["name"]):
        name = encoder["name"]
        codec = encoder.get("codecId") or name
        codec_lines.append(f"  {quoted(name)}: {quoted(codec)},")
        pixels = encoder.get("pixelFormats") or []
        if pixels:
            joined = ", ".join(quoted(p) for p in pixels)
            pixel_lines.append(f"  {quoted(name)}: <String>[{joined}],")

    body = "\n".join(
        [
            HEADER,
            "",
            "/// Codec id (the value the demuxer/muxer level calls the format) for",
            "/// every encoder the probes saw, keyed by encoder name.",
            "const Map<String, String> kEncoderCodecIds = <String, String>{",
            *codec_lines,
            "};",
            "",
            "/// Pixel formats each video encoder reports, keyed by encoder name.",
            "const Map<String, List<String>> kEncoderPixelFormats = <String, List<String>>{",
            *pixel_lines,
            "};",
            "",
        ]
    )
    (OUT / "encoder_facts.dart").write_text(body)


def write_container_codecs(matrix: dict[str, dict[str, list[str]]], known_codecs: set[str]) -> None:
    video_lines = []
    audio_lines = []
    for container in sorted(matrix):
        entry = CONTAINER_OVERRIDES.get(container, matrix[container])
        videos = [c for c in entry.get("video", []) if c in known_codecs]
        audios = [c for c in entry.get("audio", []) if c in known_codecs]
        if videos:
            joined = ", ".join(quoted(c) for c in videos)
            video_lines.append(f"  {quoted(container)}: <String>{{{joined}}},")
        if audios:
            joined = ", ".join(quoted(c) for c in audios)
            audio_lines.append(f"  {quoted(container)}: <String>{{{joined}}},")

    body = "\n".join(
        [
            HEADER,
            "",
            "/// Video codec ids each muxer accepts, measured by writing one frame.",
            "const Map<String, Set<String>> kContainerVideoCodecIds = <String, Set<String>>{",
            *video_lines,
            "};",
            "",
            "/// Audio codec ids each muxer accepts, measured the same way.",
            "const Map<String, Set<String>> kContainerAudioCodecIds = <String, Set<String>>{",
            *audio_lines,
            "};",
            "",
        ]
    )
    (OUT / "container_codecs.dart").write_text(body)


def write_extra_encoders(encoders: list[dict], curated: set[str]) -> None:
    video: list[str] = []
    audio: list[str] = []
    for encoder in sorted(encoders, key=lambda e: e["name"]):
        name = encoder["name"]
        if name in curated:
            continue
        pixels = encoder.get("pixelFormats") or []
        if encoder["kind"] == "video":
            entry = [
                "  CodecSpec(",
                f"    id: {quoted(name)},",
                f"    encoder: {quoted(name)},",
                f"    name: {quoted(name)},",
                "    kind: MediaKind.video,",
                "    options: _genericVideoOptions,",
            ]
            if pixels:
                joined = ", ".join(quoted(p) for p in pixels)
                entry.append(f"    pixelFormats: <String>[{joined}],")
            entry.append("  ),")
            video.append("\n".join(entry))
        else:
            audio.append(
                "\n".join(
                    [
                        "  CodecSpec(",
                        f"    id: {quoted(name)},",
                        f"    encoder: {quoted(name)},",
                        f"    name: {quoted(name)},",
                        "    kind: MediaKind.audio,",
                        "    options: _genericAudioOptions,",
                        "  ),",
                    ]
                )
            )

    body = "\n".join(
        [
            HEADER,
            "",
            "import '../../../i18n/i18n_keys.dart';",
            "import '../codec_spec.dart';",
            "import '../media_kind.dart';",
            "import '../option_spec.dart';",
            "",
            "/// Rate and thread controls that every software encoder understands.",
            "const List<OptionSpec> _genericVideoOptions = <OptionSpec>[",
            "  IntOption(",
            "    flag: '-q:v',",
            "    labelKey: I18nKey.optQualityScale,",
            "    min: 1,",
            "    max: 31,",
            "    exclusiveGroup: 'rate',",
            "  ),",
            "  IntOption(",
            "    flag: '-b:v',",
            "    labelKey: I18nKey.optBitrateVideo,",
            "    min: 100,",
            "    max: 100000,",
            "    unit: 'kbps',",
            "    exclusiveGroup: 'rate',",
            "  ),",
            "  IntOption(",
            "    flag: '-threads',",
            "    labelKey: I18nKey.optThreads,",
            "    min: 0,",
            "    max: 64,",
            "    advanced: true,",
            "  ),",
            "];",
            "",
            "const List<OptionSpec> _genericAudioOptions = <OptionSpec>[",
            "  IntOption(",
            "    flag: '-b:a',",
            "    labelKey: I18nKey.optBitrateAudio,",
            "    min: 8,",
            "    max: 512,",
            "    unit: 'kbps',",
            "    exclusiveGroup: 'audioRate',",
            "  ),",
            "];",
            "",
            "/// Video encoders the hand-written table does not describe.",
            "final List<CodecSpec> kExtraVideoEncoders = <CodecSpec>[",
            *video,
            "];",
            "",
            "/// Audio encoders the hand-written table does not describe.",
            "final List<CodecSpec> kExtraAudioEncoders = <CodecSpec>[",
            *audio,
            "];",
            "",
        ]
    )
    (OUT / "extra_encoders.dart").write_text(body)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    system = load("encoders-system.json")
    bundled = load("encoders-bundled.json")
    matrix = load("containers-system.json")

    merged: dict[str, dict] = {}
    for encoder in bundled + system:
        merged.setdefault(encoder["name"], encoder)
    encoders = [e for e in merged.values() if e["name"] not in EXCLUDED_ENCODERS]
    known_codecs = {e.get("codecId") or e["name"] for e in encoders}

    curated = curated_encoders()
    write_encoder_facts(encoders)
    write_baseline(bundled)
    write_container_codecs(matrix, known_codecs)
    write_extra_encoders(encoders, curated)
    print(
        f"{len(encoders)} encoders, {len(known_codecs)} codec ids, "
        f"{len(curated)} curated, {len(matrix)} containers"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
