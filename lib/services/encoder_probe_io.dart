/// Desktop and mobile probe: ask the resolved FFmpeg binary for `-encoders`.
library;

import 'dart:io';

import '../src/ffmpeg/ffmpeg_locator.dart';
import 'encoder_availability.dart';

/// ` V....D libx264  description` → video, ` A....D libopus  …` → audio.
final RegExp _encoderLine = RegExp(r'^\s([VAS])[.A-Z]{5}\s+(\S+)\s+(.*)$');

Set<String> parseEncoderNames(String output) {
  final Set<String> names = <String>{};
  for (final String line in output.split('\n')) {
    final RegExpMatch? match = _encoderLine.firstMatch(line);
    if (match == null) {
      continue;
    }
    final String kind = match.group(1)!;
    if (kind != 'V' && kind != 'A') {
      continue;
    }
    names.add(match.group(2)!);
  }
  return names;
}

Future<EncoderAvailability> probeEncoderAvailability({
  String? androidNativeLibraryDir,
}) async {
  // On Android the binary lives in the app's native library directory, which
  // only the platform side can report; without it every candidate misses and
  // the app would fall back to the bundled list even when the build carries
  // MediaCodec encoders.
  final FfmpegLocator locator = FfmpegLocator(
    androidNativeLibraryDir: androidNativeLibraryDir,
  );
  for (final FfmpegLocation location in locator.candidates()) {
    try {
      final ProcessResult result = await Process.run(
        location.path,
        const <String>['-hide_banner', '-encoders'],
        runInShell: location.isPathLookup,
      );
      if (result.exitCode != 0) {
        continue;
      }
      final Set<String> names = parseEncoderNames('${result.stdout}');
      if (names.isNotEmpty) {
        return EncoderAvailability(names: names, probed: true);
      }
    } on ProcessException {
      continue;
    } on Object {
      continue;
    }
  }
  return EncoderAvailability.baseline;
}
