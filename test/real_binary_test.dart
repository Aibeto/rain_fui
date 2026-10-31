@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_api.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_io.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_locator.dart';

void main() {
  final binary = Platform.environment['REAL_FFMPEG'];
  test('real bundled binary: initialize, run testsrc2, parse progress', () async {
    final backend = IoFfmpegBackend(
      locator: FfmpegLocator(
        environment: <String, String>{FfmpegLocator.envOverride: binary!},
        includeSystemPath: false,
      ),
    );
    addTearDown(backend.dispose);
    await backend.initialize();
    expect(backend.isAvailable, isTrue, reason: backend.unavailableReason);
    expect(await backend.version(), contains('ffmpeg version'));

    final task = await backend.run(
      FfmpegCommand(<String>[
        '-f', 'lavfi', '-i', 'testsrc2=duration=1:size=320x240:rate=25',
        '-f', 'null', '-',
      ]),
    );
    final progress = <int>[];
    task.progress.listen((p) {
      if (p.isFinal) progress.add(1);
    });
    final result = await task.done;
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('progress=end'));
    expect(progress, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)),
      skip: binary == null
          ? 'set REAL_FFMPEG=<path to a built ffmpeg> to run the end-to-end check'
          : false);
}
