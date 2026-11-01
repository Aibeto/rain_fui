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
  final List<String> attempted = <String>[];
  // On Android the binary lives in the app's native library directory, which
  // only the platform side can report; without it every candidate misses and
  // the app would fall back to the bundled list even when the build carries
  // MediaCodec encoders.
  final FfmpegLocator locator = FfmpegLocator(
    androidNativeLibraryDir: androidNativeLibraryDir,
  );
  for (final FfmpegLocation location in locator.candidates()) {
    attempted.add(location.path);
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
    } on ProcessException catch (error) {
      attempted[attempted.length - 1] = '${attempted.last} (${error.message})';
      continue;
    } on Object catch (error) {
      attempted[attempted.length - 1] = '${attempted.last} ($error)';
      continue;
    }
  }
  // Nothing ran. Say which paths were tried, so a device log shows why the
  // picker fell back instead of silently offering fewer encoders.
  return EncoderAvailability(
    names: EncoderAvailability.baselineNamesForCurrentPlatform,
    probed: false,
    error: 'no ffmpeg candidate answered -encoders: ${attempted.join(', ')}',
  );
}
