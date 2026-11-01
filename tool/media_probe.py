#!/usr/bin/env python3
"""Probe an FFmpeg binary for the facts the encode form needs.

Two jobs, both measured instead of guessed:

* which codec id every encoder produces, and which pixel/sample formats it
  accepts (parsed from `-h encoder=<name>`);
* which codec ids every container accepts (measured by writing one frame, or a
  short silent audio clip, into the muxer).

Usage:
    python3 tool/media_probe.py encoders  [--ffmpeg PATH] [--out FILE]
    python3 tool/media_probe.py containers [--ffmpeg PATH] [--out FILE]

The results are JSON and feed tool/gen_capabilities.py.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ENCODER_LINE = re.compile(r"^\s([VAS])[.A-Z]{5}\s+(\S+)\s+(.*)$")
CODEC_HINT = re.compile(r"\(codec ([a-z0-9_]+)\)")
STREAM_LINE = re.compile(r"Stream #\d+:\d+.*?: (Video|Audio): ([a-z0-9_]+)")
PIX_FMTS = re.compile(r"Supported pixel formats: (.+)")
SAMPLE_FMTS = re.compile(r"Supported sample formats: (.+)")


def run(binary: str, args: list[str], timeout: float = 30.0) -> subprocess.CompletedProcess:
    return subprocess.run(
        [binary, "-hide_banner", "-nostdin", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def list_encoders(binary: str) -> list[dict[str, str]]:
    """Every V/A encoder the binary reports, with FFmpeg's own description."""
    out = run(binary, ["-encoders"]).stdout
    encoders = []
    for line in out.splitlines():
        match = ENCODER_LINE.match(line)
        if not match:
            continue
        kind, name, description = match.groups()
        if kind not in {"V", "A"}:
            continue
        hint = CODEC_HINT.search(description)
        encoders.append(
            {
                "name": name,
                "kind": "video" if kind == "V" else "audio",
                "description": description.strip(),
                "codecHint": hint.group(1) if hint else "",
            }
        )
    return encoders


def help_formats(binary: str, encoder: str) -> tuple[list[str], list[str]]:
    """Pixel and sample formats the encoder advertises."""
    out = run(binary, ["-h", f"encoder={encoder}"]).stdout
    pixels: list[str] = []
    samples: list[str] = []
    for line in out.splitlines():
        pixel = PIX_FMTS.search(line)
        if pixel:
            pixels = pixel.group(1).split()
        sample = SAMPLE_FMTS.search(line)
        if sample:
            samples = sample.group(1).split()
    return pixels, samples


def output_stream(stderr: str) -> re.Match[str] | None:
    """Match the codec of the first stream in the output section.

    FFmpeg prints the input streams too (`color` shows up as wrapped_avframe),
    so searching the whole log picks the wrong one.
    """
    marker = stderr.find("Output #0")
    if marker < 0:
        return None
    return STREAM_LINE.search(stderr[marker:])


def probe_video(binary: str, encoder: str) -> str:
    """Codec id a video encoder actually produces, or '' when it cannot run."""
    result = run(
        binary,
        [
            "-f", "lavfi", "-i", "color=c=black:s=64x64:d=0.2",
            "-frames:v", "1", "-c:v", encoder, "-an", "-strict", "-2",
            "-f", "null", "-",
        ],
        timeout=25.0,
    )
    match = output_stream(result.stderr)
    if match and match.group(1) == "Video":
        return match.group(2)
    return ""


def probe_audio(binary: str, encoder: str) -> str:
    result = run(
        binary,
        [
            "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
            "-t", "0.1", "-c:a", encoder, "-vn", "-strict", "-2",
            "-f", "null", "-",
        ],
        timeout=25.0,
    )
    match = output_stream(result.stderr)
    if match and match.group(1) == "Audio":
        return match.group(2)
    return ""


def collect_encoders(binary: str) -> list[dict[str, object]]:
    encoders = list_encoders(binary)
    with ThreadPoolExecutor(max_workers=8) as pool:
        video = [e for e in encoders if e["kind"] == "video"]
        audio = [e for e in encoders if e["kind"] == "audio"]
        video_codecs = list(pool.map(lambda e: probe_video(binary, e["name"]), video))
        audio_codecs = list(pool.map(lambda e: probe_audio(binary, e["name"]), audio))
        video_fmts = list(pool.map(lambda e: help_formats(binary, e["name"]), video))
        audio_fmts = list(pool.map(lambda e: help_formats(binary, e["name"]), audio))

    for encoder, codec, (pixels, _) in zip(video, video_codecs, video_fmts):
        encoder["codecId"] = codec or encoder["codecHint"] or encoder["name"]
        encoder["pixelFormats"] = pixels
    for encoder, codec, (_, samples) in zip(audio, audio_codecs, audio_fmts):
        encoder["codecId"] = codec or encoder["codecHint"] or encoder["name"]
        encoder["sampleFormats"] = samples
    return encoders


def best_encoder_per_codec(binary: str) -> dict[str, dict[str, str]]:
    """One working encoder per codec id, preferring software encoders."""
    encoders = collect_encoders(binary)
    # Hardware and lib variants come later in the list than the native ones in
    # most builds, so a stable sort by (hardware, lib, name) picks native first.
    def rank(encoder: dict[str, object]) -> tuple[int, int, str]:
        name = str(encoder["name"])
        hardware = any(
            suffix in name
            for suffix in ("_nvenc", "_qsv", "_vaapi", "_amf", "_videotoolbox",
                           "_v4l2m2m", "_mediacodec", "_vulkan", "_mf", "_omx",
                           "_cuvid", "_at")
        )
        return (1 if hardware else 0, 1 if name.startswith("lib") else 0, name)

    chosen: dict[str, dict[str, str]] = {}
    for encoder in sorted(encoders, key=rank):
        codec = str(encoder.get("codecId") or "")
        if not codec:
            continue
        chosen.setdefault(codec, encoder)  # type: ignore[arg-type]
    return chosen


def encode_test(binary: str, container: str, codec: str, encoder: str, kind: str, work: Path) -> bool:
    """True when the muxer accepts a stream of this codec id."""
    target = work / f"{container}-{codec}.{container}"
    if kind == "video":
        args = [
            "-f", "lavfi", "-i", "color=c=black:s=64x64:d=0.2",
            "-frames:v", "1", "-c:v", encoder, "-an", "-strict", "-2",
            "-f", container, "-y", str(target),
        ]
    else:
        args = [
            "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
            "-t", "0.2", "-c:a", encoder, "-vn", "-strict", "-2",
            "-f", container, "-y", str(target),
        ]
    try:
        result = run(binary, args, timeout=25.0)
    except subprocess.TimeoutExpired:
        return False
    finally:
        for leftover in work.glob(f"{container}-{codec}.*"):
            leftover.unlink(missing_ok=True)
    return result.returncode == 0


def container_matrix(binary: str, containers: list[str]) -> dict[str, dict[str, list[str]]]:
    chosen = best_encoder_per_codec(binary)
    kinds = {"video": [], "audio": []}
    for codec, encoder in chosen.items():
        kinds[str(encoder["kind"])].append(codec)

    matrix: dict[str, dict[str, list[str]]] = {}
    with tempfile.TemporaryDirectory(prefix="media-probe-") as tmp:
        work = Path(tmp)
        with ThreadPoolExecutor(max_workers=8) as pool:
            for container in containers:
                tasks = []
                for kind in ("video", "audio"):
                    for codec in kinds[kind]:
                        tasks.append(
                            (kind, codec, pool.submit(
                                encode_test, binary, container, codec,
                                str(chosen[codec]["name"]), kind, work,
                            ))
                        )
                accepted = {"video": [], "audio": []}
                for kind, codec, future in tasks:
                    if future.result():
                        accepted[kind].append(codec)
                matrix[container] = {
                    "video": sorted(accepted["video"]),
                    "audio": sorted(accepted["audio"]),
                }
    return matrix


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("what", choices=["encoders", "containers"])
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--out", required=True)
    parser.add_argument("--containers", default="")
    args = parser.parse_args(argv)

    if args.what == "encoders":
        payload = collect_encoders(args.ffmpeg)
    else:
        containers = [c for c in args.containers.split(",") if c] or [
            "mp4", "mov", "matroska", "webm", "avi", "mpegts", "flv", "gif",
            "image2", "flac", "wav", "ogg", "opus", "ipod", "ac3", "adts", "wv",
            "nut", "asf", "dv", "mxf", "rawvideo", "yuv4mpegpipe", "smjpeg",
            "swf", "apng",
        ]
        payload = container_matrix(args.ffmpeg, containers)

    Path(args.out).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
