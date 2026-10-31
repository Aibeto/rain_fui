@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_api.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_io.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_locator.dart';

/// These tests drive the real [Process] plumbing with tiny POSIX shell scripts
/// that imitate FFmpeg, so no FFmpeg build is required.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('rain_fui_io'));
  tearDown(() => temp.deleteSync(recursive: true));

  File writeScript(String name, String body) {
    final file = File('${temp.path}/$name')
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    final chmod = Process.runSync('chmod', <String>['+x', file.path]);
    expect(chmod.exitCode, 0, reason: 'chmod failed: ${chmod.stderr}');
    return file;
  }

  /// A script that answers `-version`, then behaves like an encoder run.
  File fakeFfmpeg({String name = 'ffmpeg', String runBody = _defaultRunBody}) {
    return writeScript(name, '''
case " \$* " in *" -version "*) echo "ffmpeg version 9.0.2-test Copyright (c) 2000-2026"; exit 0;; esac
$runBody
''');
  }

  IoFfmpegBackend backendFor(File binary) {
    return IoFfmpegBackend(
      locator: FfmpegLocator(
        environment: <String, String>{FfmpegLocator.envOverride: binary.path},
        executablePath: '${temp.path}/app/rain_fui',
        workingDirectory: '${temp.path}/repo',
        includeSystemPath: false,
      ),
      probeTimeout: const Duration(seconds: 10),
    );
  }

  group('locating', () {
    test('initialises from the environment override', () async {
      final binary = fakeFfmpeg();
      final backend = backendFor(binary);

      await backend.initialize();

      expect(backend.isAvailable, isTrue);
      expect(backend.unavailableReason, isNull);
      expect(backend.executableDescription, binary.path);
      expect(await backend.version(), startsWith('ffmpeg version 9.0.2-test'));
      expect(backend.platform, isNotEmpty);
    });

    test('initialize is idempotent', () async {
      final backend = backendFor(fakeFfmpeg());
      await backend.initialize();
      await backend.initialize();
      expect(backend.isAvailable, isTrue);
    });

    test('rejects binaries that are not FFmpeg', () async {
      final binary = writeScript('not-ffmpeg', 'echo "hello, definitely not ffmpeg"\nexit 0');
      final backend = backendFor(binary);

      await backend.initialize();

      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, contains('Not an FFmpeg binary'));
      await expectLater(backend.version(), throwsA(isA<FfmpegNotFoundException>()));
      await expectLater(
        backend.run(FfmpegCommand(FfmpegPresets.version)),
        throwsA(isA<FfmpegNotFoundException>()),
      );
    });

    test('reports the candidates it tried when every probe fails', () async {
      final backend = IoFfmpegBackend(
        locator: FfmpegLocator(
          environment: const <String, String>{},
          executablePath: '${temp.path}/app/rain_fui',
          workingDirectory: '${temp.path}/repo',
          includeSystemPath: false,
        ),
        starter: (String executable, List<String> arguments) async =>
            throw ProcessException(executable, arguments, 'no such file', 2),
      );

      await backend.initialize();

      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, contains('No working FFmpeg binary found'));
      expect(backend.unavailableReason, contains(FfmpegLocator.envOverride));
    });
  });

  group('running', () {
    test('streams logs, parses progress and returns the exit code', () async {
      final backend = backendFor(fakeFfmpeg());
      await backend.initialize();

      final task = await backend.run(FfmpegCommand(<String>['-i', 'in.mp4', 'out.mp4']));
      final logs = <String>[];
      final progress = <FfmpegProgress>[];
      task.logs.listen(logs.add);
      task.progress.listen(progress.add);

      final result = await task.done;
      await pumpEventQueue();

      expect(result.exitCode, 0);
      expect(result.succeeded, isTrue);
      expect(task.isRunning, isFalse);
      expect(result.stdout, contains('ARG:-nostdin'));
      expect(result.stdout, contains('ARG:-progress'));
      expect(result.stdout, contains('ARG:in.mp4'));
      expect(logs, contains('ARG:-hide_banner'));
      expect(logs, contains('progress=end'));
      expect(progress, hasLength(2));
      expect(progress.first.frame, 1);
      expect(progress.last.frame, 2);
      expect(progress.last.isFinal, isTrue);
      expect(progress.last.outTime, const Duration(milliseconds: 80));
      expect(progress.last.speed, closeTo(2.0, 1e-9));
    });

    test('reports a non-zero exit code with stderr tail', () async {
      final backend = backendFor(fakeFfmpeg(runBody: 'echo "boom happened" >&2\nexit 7'));
      await backend.initialize();

      final task = await backend.run(FfmpegCommand(<String>['-i', 'broken.mp4']));
      final result = await task.done;

      expect(result.succeeded, isFalse);
      expect(result.exitCode, 7);
      expect(result.stderr, contains('boom happened'));
      expect(
        () => result.ensureSucceeded(),
        throwsA(isA<FfmpegException>().having((error) => error.exitCode, 'exitCode', 7)),
      );
    });

    test('reportProgress false yields no progress events', () async {
      final backend = backendFor(fakeFfmpeg());
      await backend.initialize();

      final task = await backend.run(
        FfmpegCommand(<String>['-i', 'in.mp4'], reportProgress: false),
      );
      final progress = <FfmpegProgress>[];
      task.progress.listen(progress.add);
      final result = await task.done;
      await pumpEventQueue();

      expect(result.stdout, isNot(contains('ARG:-progress')));
      expect(progress, isEmpty);
    });

    test('cancel terminates the process', () async {
      final backend = backendFor(fakeFfmpeg(runBody: 'echo started >&2\nexec sleep 10'));
      await backend.initialize();

      final task = await backend.run(FfmpegCommand(<String>['-i', 'long.mp4']));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(task.isRunning, isTrue);

      await task.cancel();
      final result = await task.done.timeout(const Duration(seconds: 10));

      expect(task.wasCancelled, isTrue);
      expect(task.isRunning, isFalse);
      expect(result.exitCode, isNot(0));
    });
  });
}

const String _defaultRunBody = '''
echo "Input #0, lavfi, from 'testsrc2'" >&2
for arg in "\$@"; do echo "ARG:\$arg"; done
echo "frame=1"
echo "out_time_us=40000"
echo "fps=25.0"
echo "speed=2.0x"
echo "progress=continue"
echo "frame=2"
echo "out_time_us=80000"
echo "speed=2.0x"
echo "progress=end"
exit 0
''';
