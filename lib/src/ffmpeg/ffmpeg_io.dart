import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'android_paths.dart';
import 'ffmpeg_api.dart';
import 'ffmpeg_locator.dart';
import 'replay_stream.dart';

/// Signature of the process launcher, injectable so tests can fake FFmpeg.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// Drives a native `ffmpeg` binary through [Process].
///
/// Used on Linux, Windows, macOS and Android; the web build gets
/// `ffmpeg_web.dart` instead (see the conditional import in `ffmpeg.dart`).
class IoFfmpegBackend extends FfmpegBackend {
  IoFfmpegBackend({
    this.locator,
    ProcessStarter? starter,
    this.probeTimeout = const Duration(seconds: 20),
  }) : _starter = starter ?? Process.start;

  /// Overrides automatic candidate discovery; injected by tests.
  final FfmpegLocator? locator;

  /// How long `ffmpeg -version` may take before a candidate is rejected.
  final Duration probeTimeout;

  final ProcessStarter _starter;

  final Stopwatch _clock = Stopwatch();

  Future<void>? _initializing;
  bool _initialized = false;
  String? _unavailableReason;

  FfmpegLocation? _location;
  String? _versionLine;
  FfmpegNotFoundException? _failure;

  @override
  String get platform => Platform.operatingSystem;

  @override
  bool get isAvailable => _location != null;

  @override
  String? get unavailableReason => _unavailableReason;

  @override
  String get executableDescription {
    final location = _location;
    if (location == null) return 'not found';
    return location.path;
  }

  /// Where the binary was found (null until [initialize] succeeds).
  FfmpegLocation? get location => _location;

  /// How long locating + verifying the binary took.
  Duration get initializationTime => _clock.elapsed;

  @override
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    _clock
      ..reset()
      ..start();
    try {
      if (!Platform.isLinux &&
          !Platform.isWindows &&
          !Platform.isMacOS &&
          !Platform.isAndroid) {
        _unavailableReason = Platform.isIOS
            ? 'iOS cannot spawn subprocesses; FFmpeg support is unavailable.'
            : 'Unsupported platform: ${Platform.operatingSystem}.';
        return;
      }

      final locator = await _buildLocator();
      final candidates = locator.candidates();
      if (candidates.isEmpty) {
        _unavailableReason =
            'No FFmpeg candidate paths for ${Platform.operatingSystem}.';
        return;
      }

      final failures = <String>[];
      for (final candidate in candidates) {
        try {
          _versionLine = await _probe(candidate.path);
          _location = candidate;
          return;
        } on Object catch (error) {
          failures.add('${candidate.path}: ${_shortError(error)}');
        }
      }

      _failure = FfmpegNotFoundException(
        'No working FFmpeg binary found. Build it with scripts/ffmpeg/build-<target>.sh '
        'or set ${FfmpegLocator.envOverride} to an existing binary.\nTried:\n  '
        '${failures.join('\n  ')}',
      );
      _unavailableReason = _failure!.message;
    } finally {
      _clock.stop();
      _initialized = true;
    }
  }

  Future<FfmpegLocator> _buildLocator() async {
    if (locator != null) return locator!;
    final nativeLibDir = Platform.isAndroid
        ? await AndroidPaths.nativeLibraryDir()
        : null;
    return FfmpegLocator(
      androidNativeLibraryDir: nativeLibDir,
      executableSuffix: Platform.isWindows ? '.exe' : '',
    );
  }

  /// Runs `ffmpeg -version` and returns its first line, proving the binary is
  /// executable and is really FFmpeg.
  Future<String> _probe(String executable) async {
    final process = await _starter(executable, const <String>[
      '-version',
    ]).timeout(probeTimeout);
    // `-version` never reads stdin; leaving the pipe open keeps a handle per
    // probe and can make a stubborn binary wait for input.
    unawaited(process.stdin.close().catchError((Object _) {}));
    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final exitCode = await process.exitCode.timeout(
      probeTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('ffmpeg -version timed out', probeTimeout);
      },
    );
    final stdout = await stdoutFuture;
    await stderrFuture;

    if (exitCode != 0) {
      throw FfmpegException(
        '`-version` exited with code $exitCode',
        exitCode: exitCode,
      );
    }
    final firstLine = stdout
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    if (!firstLine.contains('ffmpeg version')) {
      throw FfmpegException(
        'Not an FFmpeg binary (stdout: ${firstLine.trim()})',
      );
    }
    return firstLine.trim();
  }

  @override
  Future<String> version() async {
    await initialize();
    final line = _versionLine;
    if (line == null) {
      throw _failure ??
          FfmpegNotFoundException(_unavailableReason ?? 'FFmpeg unavailable');
    }
    return line;
  }

  @override
  Future<FfmpegTask> run(FfmpegCommand command) async {
    await initialize();
    final location = _location;
    if (location == null) {
      throw _failure ??
          FfmpegNotFoundException(
            _unavailableReason ?? 'FFmpeg is not available on this platform',
          );
    }
    final argv = command.toArgv();
    try {
      final process = await _starter(location.path, argv);
      return IoFfmpegTask(process: process, command: command, argv: argv);
    } on Object catch (error) {
      throw FfmpegException('Cannot start ${location.path}', cause: error);
    }
  }

  @override
  Future<void> dispose() async {
    // Nothing cached that needs releasing; kept for interface symmetry.
  }

  static String _shortError(Object error) {
    if (error is FfmpegException) return error.message;
    if (error is TimeoutException) return 'timed out';
    final text = error.toString().replaceAll('\n', ' ');
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}

/// One running native FFmpeg process.
class IoFfmpegTask implements FfmpegTask {
  IoFfmpegTask({
    required this.process,
    required this.command,
    required this.argv,
  }) {
    _bind();
  }

  /// The spawned process.
  final Process process;

  /// The invocation this task is running.
  final FfmpegCommand command;

  /// The exact argv that was executed (including injected global flags).
  final List<String> argv;

  final ReplayStream<String> _logs = ReplayStream<String>(capacity: 4000);
  final ReplayStream<FfmpegProgress> _progress = ReplayStream<FfmpegProgress>(
    capacity: 128,
  );
  final Completer<FfmpegResult> _done = Completer<FfmpegResult>();
  final FfmpegProgressParser _parser = FfmpegProgressParser();
  final _TailBuffer _stdout = _TailBuffer();
  final _TailBuffer _stderr = _TailBuffer();
  final Stopwatch _wallClock = Stopwatch()..start();

  Timer? _killTimer;
  bool _running = true;
  bool _cancelRequested = false;

  @override
  Stream<String> get logs => _logs.stream;

  @override
  Stream<FfmpegProgress> get progress => _progress.stream;

  @override
  Future<FfmpegResult> get done => _done.future;

  @override
  bool get isRunning => _running;

  /// True when [cancel] was called (the exit code will be non-zero).
  @override
  bool get wasCancelled => _cancelRequested;

  void _bind() {
    if (!command.allowStdin) {
      // `-nostdin` already tells FFmpeg to ignore stdin; closing the pipe also
      // guarantees the child can never block waiting for it.
      unawaited(process.stdin.close().catchError((Object _) {}));
    }

    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) {
            _stdout.add(line);
            _emit(line);
            if (command.reportProgress) {
              final block = _parser.addLine(line);
              if (block != null) _progress.add(block);
            }
          },
          onError: (Object error) => _stderr.add('stdout error: $error'),
          cancelOnError: false,
        )
        .asFuture<void>();

    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) {
            _stderr.add(line);
            _emit(line);
          },
          onError: (Object error) => _stderr.add('stderr error: $error'),
          cancelOnError: false,
        )
        .asFuture<void>();

    Future.wait<void>(<Future<void>>[stdoutDone, stderrDone])
        .then((_) => process.exitCode)
        .then(_complete, onError: _completeWithError);
  }

  void _emit(String line) => _logs.add(line);

  void _complete(int exitCode) {
    _killTimer?.cancel();
    _running = false;
    _wallClock.stop();
    final result = FfmpegResult(
      args: command.args,
      exitCode: exitCode,
      stdout: _stdout.text,
      stderr: _stderr.text,
      wallClock: _wallClock.elapsed,
    );
    if (!_done.isCompleted) _done.complete(result);
    _closeStreams();
  }

  void _completeWithError(Object error) {
    _killTimer?.cancel();
    _running = false;
    _wallClock.stop();
    _stderr.add('process error: $error');
    final result = FfmpegResult(
      args: command.args,
      exitCode: -1,
      stdout: _stdout.text,
      stderr: _stderr.text,
      wallClock: _wallClock.elapsed,
    );
    if (!_done.isCompleted) _done.complete(result);
    _closeStreams();
  }

  void _closeStreams() {
    unawaited(_logs.close());
    unawaited(_progress.close());
  }

  /// True while the process is parked by [suspend].
  bool _suspended = false;

  @override
  Future<bool> suspend() async {
    if (!_running || _suspended || Platform.isWindows) return false;
    try {
      _suspended = process.kill(ProcessSignal.sigstop);
      return _suspended;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> resume() async {
    if (!_running || !_suspended) return false;
    try {
      final bool sent = process.kill(ProcessSignal.sigcont);
      if (sent) _suspended = false;
      return sent;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    if (Platform.isWindows) {
      process.kill();
      return;
    }
    process.kill(ProcessSignal.sigterm);
    _killTimer = Timer(const Duration(seconds: 3), () {
      if (_running) process.kill(ProcessSignal.sigkill);
    });
  }
}

/// Keeps the last [_limit] characters of a log so a chatty run cannot exhaust
/// memory, while still surfacing the tail where the errors are.
class _TailBuffer {
  static const int _limit = 256 * 1024;
  final List<String> _chunks = <String>[];
  int _length = 0;
  bool _truncated = false;

  void add(String line) {
    final chunk = '$line\n';
    _chunks.add(chunk);
    _length += chunk.length;
    while (_length > _limit && _chunks.length > 1) {
      _length -= _chunks.removeAt(0).length;
      _truncated = true;
    }
  }

  String get text {
    final joined = _chunks.join();
    return _truncated ? '[...earlier output truncated...]\n$joined' : joined;
  }
}

/// Entry point used by the conditional import in `ffmpeg.dart`.
FfmpegBackend createPlatformFfmpegBackend() => IoFfmpegBackend();
