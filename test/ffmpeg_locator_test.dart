import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain_fui/src/ffmpeg/ffmpeg_locator.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('rain_fui_locator'));
  tearDown(() => temp.deleteSync(recursive: true));

  FfmpegLocator locatorWith({
    Map<String, String> environment = const <String, String>{},
    bool includeSystemPath = false,
  }) {
    return FfmpegLocator(
      environment: environment,
      executablePath: '${temp.path}/app/rain_fui',
      workingDirectory: '${temp.path}/repo',
      includeSystemPath: includeSystemPath,
      executableSuffix: Platform.isWindows ? '.exe' : '',
    );
  }

  File touch(String relativePath) {
    final file = File('${temp.path}/$relativePath');
    file.createSync(recursive: true);
    return file;
  }

  test('supported on this host', () {
    expect(locatorWith().isPlatformSupported, isTrue);
  });

  test('environment override is first and de-duplicated', () {
    final binary = touch('custom/ffmpeg');
    final locator = locatorWith(
      environment: <String, String>{
        FfmpegLocator.envOverride: binary.path,
        FfmpegLocator.envFallback: binary.path,
      },
    );

    final candidates = locator.candidates();
    expect(candidates, isNotEmpty);
    expect(candidates.first.path, binary.path);
    expect(candidates.first.source, FfmpegLocationSource.environment);
    expect(candidates.where((candidate) => candidate.path == binary.path), hasLength(1));
  });

  test('fallback variable is used when the primary one is empty', () {
    final binary = touch('custom/ffmpeg');
    final locator = locatorWith(
      environment: <String, String>{
        FfmpegLocator.envOverride: '   ',
        FfmpegLocator.envFallback: binary.path,
      },
    );
    expect(locator.candidates().first.path, binary.path);
  });

  test('bundled paths are preferred over repo build output', () {
    final suffix = Platform.isWindows ? '.exe' : '';
    // Mirrors the install rules in linux/CMakeLists.txt and windows/CMakeLists.txt.
    final bundled = Platform.isWindows
        ? touch('app/ffmpeg$suffix')
        : touch('app/lib/ffmpeg$suffix');
    touch('repo/linux/ffmpeg/ffmpeg$suffix');
    touch('repo/build/ffmpeg/dist/linux-x64/ffmpeg$suffix');

    final candidates = locatorWith().candidates();
    expect(candidates.first.path, bundled.path);
    expect(candidates.first.source, FfmpegLocationSource.bundled);
  });

  test('existing files are listed before missing ones', () {
    final suffix = Platform.isWindows ? '.exe' : '';
    final dev = Platform.isWindows
        ? touch('repo/windows/ffmpeg/ffmpeg$suffix')
        : touch('repo/linux/ffmpeg/ffmpeg$suffix');

    final candidates = locatorWith().candidates();
    expect(candidates.first.path, dev.path);
    expect(candidates.first.source, FfmpegLocationSource.development);
    expect(candidates.last.exists, isFalse);
  });

  test('PATH lookup is opt-in and comes last', () {
    expect(locatorWith().candidates().any((candidate) => candidate.isPathLookup), isFalse);

    final withPath = locatorWith(includeSystemPath: true).candidates();
    expect(withPath.last.isPathLookup, isTrue);
    expect(withPath.last.source, FfmpegLocationSource.systemPath);
    expect(withPath.last.path, Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg');
  });

  test('absolute paths are not treated as PATH lookups', () {
    expect(const FfmpegLocation('/usr/bin/ffmpeg', FfmpegLocationSource.bundled).isPathLookup, isFalse);
    expect(const FfmpegLocation('ffmpeg', FfmpegLocationSource.systemPath).isPathLookup, isTrue);
  });

  test('missing bare commands are assumed to exist', () {
    // The backend verifies them by running `-version`.
    expect(const FfmpegLocation('ffmpeg', FfmpegLocationSource.systemPath).exists, isTrue);
    expect(const FfmpegLocation('/definitely/not/here/ffmpeg', FfmpegLocationSource.bundled).exists, isFalse);
  });
}
