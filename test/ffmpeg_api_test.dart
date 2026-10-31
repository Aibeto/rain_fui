import 'package:flutter_test/flutter_test.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_api.dart';

void main() {
  group('splitCommandArgs', () {
    test('splits on whitespace', () {
      expect(splitCommandArgs('-i a.mp4 -c:v mpeg4'), <String>['-i', 'a.mp4', '-c:v', 'mpeg4']);
    });

    test('keeps quoted groups together and strips the quotes', () {
      expect(splitCommandArgs('-i "my video.mp4"'), <String>['-i', 'my video.mp4']);
      expect(splitCommandArgs("-i 'my video.mp4'"), <String>['-i', 'my video.mp4']);
    });

    test('honours backslash escapes outside quotes', () {
      expect(splitCommandArgs(r'-i my\ video.mp4'), <String>['-i', 'my video.mp4']);
    });

    test('supports empty quoted arguments', () {
      expect(splitCommandArgs('""'), <String>['']);
    });

    test('ignores extra whitespace', () {
      expect(splitCommandArgs('   '), isEmpty);
      expect(splitCommandArgs('  -y   out.mp4 '), <String>['-y', 'out.mp4']);
    });

    test('rejects unterminated quotes', () {
      expect(() => splitCommandArgs('-i "oops'), throwsFormatException);
    });
  });

  group('FfmpegCommand', () {
    test('injects global flags before user arguments', () {
      final command = FfmpegCommand(<String>['-i', 'in.mp4', 'out.mp4']);
      expect(command.toArgv(), <String>[
        '-hide_banner',
        '-nostdin',
        '-nostats',
        '-progress',
        'pipe:1',
        '-i',
        'in.mp4',
        'out.mp4',
      ]);
    });

    test('does not duplicate an explicit -progress', () {
      final command = FfmpegCommand(<String>['-progress', 'pipe:1', '-i', 'in.mp4']);
      final argv = command.toArgv();
      expect(argv.where((arg) => arg == '-progress'), hasLength(1));
      expect(argv, isNot(contains('-nostats')));
    });

    test('allowStdin keeps stdin open', () {
      final command = FfmpegCommand(<String>['-i', 'in.mp4'], allowStdin: true);
      expect(command.toArgv(), isNot(contains('-nostdin')));
    });

    test('reportProgress false omits progress plumbing', () {
      final command = FfmpegCommand(<String>['-i', 'in.mp4'], reportProgress: false);
      expect(command.toArgv(), <String>['-hide_banner', '-nostdin', '-i', 'in.mp4']);
    });

    test('rejects empty argument lists', () {
      expect(() => FfmpegCommand(const <String>[]), throwsArgumentError);
    });

    test('keeps the user arguments immutable', () {
      final args = <String>['-y', 'out.mp4'];
      final command = FfmpegCommand(args);
      args.add('-an');
      expect(command.args, <String>['-y', 'out.mp4']);
    });
  });

  group('progress parsing', () {
    test('parses microseconds, speed and final flag', () {
      final parser = FfmpegProgressParser();
      expect(parser.addLine('frame=42'), isNull);
      expect(parser.addLine('fps=25.0'), isNull);
      expect(parser.addLine('bitrate= 512.0kbits/s'), isNull);
      expect(parser.addLine('total_size=1024'), isNull);
      expect(parser.addLine('out_time_us=1680000'), isNull);
      expect(parser.addLine('speed=1.02x'), isNull);

      final progress = parser.addLine('progress=continue');
      expect(progress, isNotNull);
      expect(progress!.frame, 42);
      expect(progress.fps, 25.0);
      expect(progress.totalSize, 1024);
      expect(progress.bitrateKbps, 512);
      expect(progress.outTime, const Duration(microseconds: 1680000));
      expect(progress.speed, closeTo(1.02, 1e-9));
      expect(progress.isFinal, isFalse);
    });

    test('a block can be followed by another block', () {
      final parser = FfmpegProgressParser();
      parser.addLine('frame=1');
      expect(parser.addLine('progress=continue')!.frame, 1);
      parser.addLine('frame=2');
      final second = parser.addLine('progress=end');
      expect(second!.frame, 2);
      expect(second.isFinal, isTrue);
    });

    test('tolerates N/A and missing values', () {
      final parser = FfmpegProgressParser();
      parser.addLine('speed=N/A');
      parser.addLine('fps=N/A');
      final progress = parser.addLine('progress=continue')!;
      expect(progress.speed, isNull);
      expect(progress.fps, isNull);
      expect(progress.outTime, isNull);
      expect(progress.frame, isNull);
    });

    test('falls back to out_time when microseconds are absent', () {
      final parser = FfmpegProgressParser();
      parser.addLine('out_time=00:00:02.50');
      expect(parser.addLine('progress=continue')!.outTime, const Duration(milliseconds: 2500));
    });

    test('ignores lines without a key/value shape', () {
      final parser = FfmpegProgressParser();
      expect(parser.addLine('Press [q] to stop'), isNull);
      expect(parser.addLine(''), isNull);
    });

    test('parseFfmpegTimestamp handles valid and junk input', () {
      expect(parseFfmpegTimestamp('00:00:00.000000'), Duration.zero);
      expect(parseFfmpegTimestamp('01:02:03.25'), const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 250));
      expect(parseFfmpegTimestamp('n/a'), isNull);
      expect(parseFfmpegTimestamp('12:34'), isNull);
      expect(parseFfmpegTimestamp(null), isNull);
    });
  });

  group('FfmpegResult', () {
    test('ensureSucceeded is a no-op on zero', () {
      const result = FfmpegResult(args: <String>[], exitCode: 0, stdout: '', stderr: '', wallClock: Duration.zero);
      expect(result.ensureSucceeded(), same(result));
    });

    test('ensureSucceeded keeps only the stderr tail', () {
      final stderr = List<String>.generate(20, (index) => 'line $index').join('\n');
      final result = FfmpegResult(args: <String>[], exitCode: 2, stdout: '', stderr: stderr, wallClock: Duration.zero);
      expect(
        () => result.ensureSucceeded(),
        throwsA(isA<FfmpegException>()
            .having((e) => e.exitCode, 'exitCode', 2)
            .having((e) => e.stderr, 'stderr', allOf(contains('line 19'), isNot(contains('line 0'))))),
      );
    });
  });
}
