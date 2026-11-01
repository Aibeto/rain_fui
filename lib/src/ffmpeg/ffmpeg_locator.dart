import 'dart:io';

/// Where a candidate FFmpeg binary came from, ordered by trustworthiness.
enum FfmpegLocationSource {
  /// Explicit `RAIN_FUI_FFMPEG_BIN` / `FFMPEG_BIN` environment variable.
  environment,

  /// Shipped next to the application bundle.
  bundled,

  /// Repo-local build output (developer machines only).
  development,

  /// A bare `ffmpeg` resolved through `PATH`.
  systemPath,
}

/// One place where an FFmpeg binary might live.
class FfmpegLocation {
  const FfmpegLocation(this.path, this.source);

  final String path;
  final FfmpegLocationSource source;

  /// True for a bare command name such as `ffmpeg`, which [Process.start]
  /// resolves through `PATH` instead of treating as a file path.
  bool get isPathLookup => !path.contains('/') && !path.contains(r'\');

  /// Existence check. A bare command name is assumed to exist; the backend
  /// verifies it by actually running `-version`.
  bool get exists => isPathLookup ? true : File(path).existsSync();

  @override
  String toString() => 'FfmpegLocation($path, ${source.name})';
}

/// Computes the ordered list of places to look for FFmpeg on this host.
///
/// The search order is fixed by `docs/build-contract.md`:
/// environment override → application bundle → developer build output → `PATH`.
class FfmpegLocator {
  FfmpegLocator({
    Map<String, String>? environment,
    String? executablePath,
    String? workingDirectory,
    this.androidNativeLibraryDir,
    this.executableSuffix = '',
    this.includeSystemPath = true,
  }) : _environment = environment ?? Platform.environment,
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       _workingDirectory = workingDirectory ?? _safeCurrentDirectory();

  static const String envOverride = 'RAIN_FUI_FFMPEG_BIN';
  static const String envFallback = 'FFMPEG_BIN';

  final Map<String, String> _environment;
  final String _executablePath;
  final String _workingDirectory;

  /// Filled in on Android from `ApplicationInfo.nativeLibraryDir` (see
  /// `android_paths.dart`); null elsewhere.
  final String? androidNativeLibraryDir;

  /// `.exe` on Windows, empty otherwise.
  final String executableSuffix;

  /// Whether to fall back to a bare `ffmpeg` resolved through `PATH`.
  /// Disable it to keep behaviour hermetic (tests, sandboxed deployments).
  final bool includeSystemPath;

  static String _safeCurrentDirectory() {
    try {
      return Directory.current.path;
    } on Object {
      return '';
    }
  }

  /// iOS cannot spawn subprocesses at all, so there is nothing to locate.
  bool get isPlatformSupported =>
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isAndroid;

  /// Ordered, de-duplicated candidates. Existing files come first so the
  /// backend wastes no time spawning impossible paths.
  List<FfmpegLocation> candidates() {
    if (!isPlatformSupported) return const <FfmpegLocation>[];

    final all = <FfmpegLocation>[
      ..._environmentCandidates(),
      ..._bundledCandidates(),
      ..._developmentCandidates(),
      ..._pathCandidates(),
    ];

    final seen = <String>{};
    final existing = <FfmpegLocation>[];
    final missing = <FfmpegLocation>[];
    final lookups = <FfmpegLocation>[];
    for (final location in all) {
      if (!seen.add(location.path)) continue;
      if (location.isPathLookup) {
        // A bare `ffmpeg` cannot be stat'ed, and it must stay the last resort
        // so a broken system install never shadows a bundled build.
        lookups.add(location);
      } else {
        (location.exists ? existing : missing).add(location);
      }
    }
    return <FfmpegLocation>[...existing, ...missing, ...lookups];
  }

  Iterable<FfmpegLocation> _environmentCandidates() sync* {
    for (final key in const <String>[envOverride, envFallback]) {
      final value = _environment[key];
      if (value != null && value.trim().isNotEmpty) {
        yield FfmpegLocation(value.trim(), FfmpegLocationSource.environment);
      }
    }
  }

  Iterable<FfmpegLocation> _bundledCandidates() sync* {
    final exeDir = _directoryOf(_executablePath);
    if (exeDir.isEmpty) return;
    final name = 'ffmpeg$executableSuffix';

    if (Platform.isAndroid) {
      final libDir = androidNativeLibraryDir;
      if (libDir != null && libDir.isNotEmpty) {
        // Built as an executable but shipped with an .so suffix so that it
        // lands in nativeLibraryDir, the only exec-capable location on
        // Android 10+.
        yield FfmpegLocation(
          _join(libDir, 'libffmpeg_exe.so'),
          FfmpegLocationSource.bundled,
        );
        yield FfmpegLocation(
          _join(libDir, 'libffmpeg.so'),
          FfmpegLocationSource.bundled,
        );
      }
      return;
    }

    if (Platform.isMacOS) {
      yield FfmpegLocation(
        _join(_join(exeDir, '..'), 'Frameworks/$name'),
        FfmpegLocationSource.bundled,
      );
      yield FfmpegLocation(
        _join(_join(exeDir, '..'), 'Resources/$name'),
        FfmpegLocationSource.bundled,
      );
    }

    if (Platform.isLinux) {
      // linux/CMakeLists.txt installs the program into INSTALL_BUNDLE_LIB_DIR
      // (= <bundle>/lib) under its own name, so the shipped path is the *file*
      // <bundle>/lib/ffmpeg. The directory layout is accepted as a fallback.
      yield FfmpegLocation(
        _join(exeDir, 'lib/$name'),
        FfmpegLocationSource.bundled,
      );
      yield FfmpegLocation(
        _join(exeDir, 'lib/ffmpeg/$name'),
        FfmpegLocationSource.bundled,
      );
      yield FfmpegLocation(
        _join(_join(exeDir, '..'), 'lib/$name'),
        FfmpegLocationSource.bundled,
      );
      yield FfmpegLocation(
        _join(_join(exeDir, '..'), 'lib/ffmpeg/$name'),
        FfmpegLocationSource.bundled,
      );
    }

    if (Platform.isWindows) {
      // ffmpeg.exe next to rain_fui.exe — installed by windows/CMakeLists.txt.
      yield FfmpegLocation(_join(exeDir, name), FfmpegLocationSource.bundled);
    }
  }

  Iterable<FfmpegLocation> _developmentCandidates() sync* {
    if (_workingDirectory.isEmpty) return;
    final name = 'ffmpeg$executableSuffix';

    if (Platform.isLinux) {
      yield FfmpegLocation(
        _join(_workingDirectory, 'linux/ffmpeg/$name'),
        FfmpegLocationSource.development,
      );
      yield FfmpegLocation(
        _join(_workingDirectory, 'build/ffmpeg/dist/linux-x64/$name'),
        FfmpegLocationSource.development,
      );
    } else if (Platform.isWindows) {
      yield FfmpegLocation(
        _join(_workingDirectory, 'windows/ffmpeg/$name'),
        FfmpegLocationSource.development,
      );
      yield FfmpegLocation(
        _join(_workingDirectory, 'build/ffmpeg/dist/windows-x64/$name'),
        FfmpegLocationSource.development,
      );
    }
  }

  Iterable<FfmpegLocation> _pathCandidates() sync* {
    if (!includeSystemPath) return;
    if (Platform.isAndroid) return; // No POSIX PATH for app processes.
    yield FfmpegLocation(
      'ffmpeg$executableSuffix',
      FfmpegLocationSource.systemPath,
    );
  }

  static String _directoryOf(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    if (index <= 0) return '';
    return path.substring(0, index);
  }

  static String _join(String base, String child) {
    if (base.endsWith('/') || base.endsWith(r'\')) return '$base$child';
    return '$base${Platform.pathSeparator}$child';
  }
}
