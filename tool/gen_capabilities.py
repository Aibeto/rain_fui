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

# The probe only sees what one Linux build can run. These are the encoders other
# builds have: platform back ends (MediaCodec, MediaFoundation, VideoToolbox,
# D3D12, Rockchip, OpenHarmony) and third-party libraries that are not installed
# here. Name -> (kind, codec id). They stay in the table so a Windows, Android or
# macOS build shows them; a build without them never offers them.
EXTRA_ENCODERS: dict[str, tuple[str, str]] = {
    # Apple AudioToolbox
    "aac_at": ("audio", "aac"),
    "alac_at": ("audio", "alac"),
    "ilbc_at": ("audio", "ilbc"),
    "pcm_alaw_at": ("audio", "pcm_alaw"),
    "pcm_mulaw_at": ("audio", "pcm_mulaw"),
    # Windows MediaFoundation
    "aac_mf": ("audio", "aac"),
    "ac3_mf": ("audio", "ac3"),
    "mp3_mf": ("audio", "mp3"),
    "h264_mf": ("video", "h264"),
    "hevc_mf": ("video", "hevc"),
    "av1_mf": ("video", "av1"),
    # Android MediaCodec
    "h264_mediacodec": ("video", "h264"),
    "hevc_mediacodec": ("video", "hevc"),
    "mpeg4_mediacodec": ("video", "mpeg4"),
    "vp8_mediacodec": ("video", "vp8"),
    "vp9_mediacodec": ("video", "vp9"),
    "av1_mediacodec": ("video", "av1"),
    # Apple VideoToolbox
    "h264_videotoolbox": ("video", "h264"),
    "hevc_videotoolbox": ("video", "hevc"),
    "prores_videotoolbox": ("video", "prores"),
    # Direct3D 12, Rockchip, OpenHarmony
    "h264_d3d12va": ("video", "h264"),
    "hevc_d3d12va": ("video", "hevc"),
    "av1_d3d12va": ("video", "av1"),
    "h264_rkmpp": ("video", "h264"),
    "hevc_rkmpp": ("video", "hevc"),
    "h264_oh": ("video", "h264"),
    "hevc_oh": ("video", "hevc"),
    # Third-party libraries not installed on this host
    "libfdk_aac": ("audio", "aac"),
    "libilbc": ("audio", "ilbc"),
    "liblc3": ("audio", "lc3"),
    "libvo_amrwbenc": ("audio", "amrwb"),
    "libshine": ("audio", "mp3"),
    "libtwolame": ("audio", "mp2"),
    "libcodec2": ("audio", "codec2"),
    "libkvazaar": ("video", "hevc"),
    "libopenh264": ("video", "h264"),
    "libvvenc": ("video", "vvc"),
    "libx262": ("video", "mpeg2video"),
    "libxavs": ("video", "cavs"),
    "libxavs2": ("video", "cavs2"),
    "libxeve": ("video", "evc"),
    "libsvtjpegxs": ("video", "jpegxs"),
    "liboapv": ("video", "apv"),
}

# allcodecs.c names its encoders after the C symbol, which is not always the
# name `-c:v` takes. Anything here is already covered by a probe entry.
SYMBOL_ALIASES: dict[str, str] = {
    "libaom_av1": "libaom-av1",
    "libvpx_vp8": "libvpx",
    "libvpx_vp9": "libvpx-vp9",
    "msmpeg4v3": "msmpeg4",
    "ra_144": "real_144",
    "roq": "roqvideo",
    "adpcm_g722": "g722",
    "adpcm_g726": "g726",
    "adpcm_g726le": "g726le",
}

# Subtitle and data encoders: the form only writes audio and video streams.
SKIP_KINDS = {
    "ass", "dvbsub", "dvdsub", "movtext", "srt", "ssa", "subrip", "text",
    "ttml", "webvtt", "xsub",
}

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
    # The Ogg muxer accepts every Ogg payload; Speex is a Speex container.
    "spx": {"video": [], "audio": ["speex"]},
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


def uncovered_symbols(names: set[str]) -> list[str]:
    """Symbols in allcodecs.c that neither a probe nor a mapping accounts for."""
    source = (ROOT / "third_party" / "ffmpeg" / "libavcodec" / "allcodecs.c").read_text()
    symbols = set(re.findall(r"ff_([a-z0-9_]+)_encoder", source))
    missing = []
    for symbol in sorted(symbols):
        if symbol in {"codec_is", *EXCLUDED_ENCODERS}:
            continue  # ff_codec_is_encoder is a helper, not an encoder
        if symbol in names or symbol in SKIP_KINDS:
            continue
        if SYMBOL_ALIASES.get(symbol) in names:
            continue
        missing.append(symbol)
    return missing


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    system = load("encoders-system.json")
    bundled = load("encoders-bundled.json")
    matrix = load("containers-system.json")

    merged: dict[str, dict] = {}
    for encoder in bundled + system:
        merged.setdefault(encoder["name"], encoder)
    for name, (kind, codec) in EXTRA_ENCODERS.items():
        merged.setdefault(
            name,
            {
                "name": name,
                "kind": kind,
                "codecId": codec,
                "codecHint": codec,
                "description": "",
            },
        )
    encoders = [e for e in merged.values() if e["name"] not in EXCLUDED_ENCODERS]
    known_codecs = {e.get("codecId") or e["name"] for e in encoders}

    curated = curated_encoders()
    write_encoder_facts(encoders)
    write_baseline(bundled)
    write_container_codecs(matrix, known_codecs)
    write_extra_encoders(encoders, curated)
    uncovered = uncovered_symbols({e["name"] for e in encoders})
    print(
        f"{len(encoders)} encoders, {len(known_codecs)} codec ids, "
        f"{len(curated)} curated, {len(matrix)} containers"
    )
    if uncovered:
        print("uncovered encoder symbols: " + " ".join(uncovered))
        return 1
    print("every encoder symbol in allcodecs.c is covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
