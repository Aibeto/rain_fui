import 'dart:async';
import 'dart:js_interop';

import 'ffmpeg_api.dart';
import 'replay_stream.dart';

/// The JS bridge defined in `web/ffmpeg/ffmpeg_bridge.js`.
@JS('rainFfmpeg')
external JSAny? get _rainFfmpegRaw;

extension type _FfmpegBridge._(JSObject _) implements JSObject {
  external JSPromise<JSObject> init();
  external JSPromise<JSObject> run(JSArray<JSString> args, JSFunction onLine);
  external void cancel();
  external void download(String virtualPath, String downloadName);
}

extension type _InitResult._(JSObject _) implements JSObject {
  external bool get ok;
  external String get version;
  external String get error;
}

extension type _RunResult._(JSObject _) implements JSObject {
  external int get exitCode;
  external String get stdout;
  external String get stderr;
}

/// Runs FFmpeg as WebAssembly inside a dedicated Web Worker.
///
/// Each run boots a fresh Emscripten instance: `ffmpeg` calls `exit()`, which
/// poisons the module for further use.
class WebFfmpegBackend extends FfmpegBackend {
  _FfmpegBridge? _bridge;
  Future<void>? _initializing;
  bool _initialized = false;
  bool _available = false;
  String? _unavailableReason;
  String _versionLine = '';

  @override
  String get platform => 'web';

  @override
  bool get isAvailable => _available;

  @override
  String? get unavailableReason => _unavailableReason;

  @override
  String get executableDescription => _available ? 'wasm (web)' : 'not found';

  @override
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final raw = _rainFfmpegRaw;
      if (raw == null) {
        _unavailableReason =
            'web/ffmpeg/ffmpeg_bridge.js is not loaded. Build the web core with '
            'scripts/ffmpeg/build-web.sh.';
        return;
      }
      final bridge = _bridge = _FfmpegBridge._(raw as JSObject);
      final result = _InitResult._(await bridge.init().toDart);
      if (!result.ok) {
        _unavailableReason = result.error.isEmpty
            ? 'Failed to initialise the FFmpeg wasm module.'
            : result.error;
        return;
      }
      _versionLine = result.version;
      _available = true;
    } on Object catch (error) {
      _unavailableReason = 'FFmpeg wasm bridge failed: $error';
    } finally {
      _initialized = true;
    }
  }

  @override
  Future<String> version() async {
    await initialize();
    if (!_available) {
      throw FfmpegNotFoundException(
        _unavailableReason ?? 'FFmpeg is unavailable',
      );
    }
    return _versionLine;
  }

  @override
  Future<FfmpegTask> run(FfmpegCommand command) async {
    await initialize();
    final bridge = _bridge;
    if (!_available || bridge == null) {
      throw FfmpegNotFoundException(
        _unavailableReason ?? 'FFmpeg is unavailable',
      );
    }

    final task = WebFfmpegTask._(command: command, onCancel: () => bridge.cancel());
    final argv = command.toArgv().map((arg) => arg.toJS).toList().toJS;
    final onLine = ((JSString stream, JSString line) {
      task.handleLine(stream.toDart, line.toDart);
    }).toJS;
    task.start(bridge.run(argv, onLine));
    return task;
  }

  @override
  Future<void> dispose() async {
    _bridge?.cancel();
  }

  @override
  Future<bool> saveOutputFile(
    String virtualPath, {
    String? downloadName,
  }) async {
    final bridge = _bridge;
    if (!_available || bridge == null) return false;
    try {
      final name = downloadName ?? virtualPath.split('/').last;
      bridge.download(virtualPath, name);
      return true;
    } on Object {
      return false;
    }
  }
}

/// One running wasm FFmpeg invocation.
class WebFfmpegTask implements FfmpegTask {
  WebFfmpegTask._({required FfmpegCommand command, required this.onCancel})
    : _command = command,
      _argv = command.toArgv();

  final FfmpegCommand _command;
  final List<String> _argv;

  /// Tears the wasm worker down; injected by the backend.
  final void Function() onCancel;

  final ReplayStream<String> _logs = ReplayStream<String>(capacity: 4000);
  final ReplayStream<FfmpegProgress> _progress = ReplayStream<FfmpegProgress>(
    capacity: 128,
  );
  final Completer<FfmpegResult> _done = Completer<FfmpegResult>();
  final FfmpegProgressParser _parser = FfmpegProgressParser();
  final Stopwatch _wallClock = Stopwatch()..start();

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

  @override
  bool get wasCancelled => _cancelRequested;

  List<String> get argv => _argv;

  void start(JSPromise<JSObject> promise) {
    _wallClock.start();
    promise.toDart.then(
      (value) {
        final result = _RunResult._(value);
        _complete(
          result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr,
        );
      },
      onError: (Object error) {
        _complete(-1, stdout: '', stderr: 'worker error: $error');
      },
    );
  }

  /// Called from the JS bridge for every line FFmpeg writes.
  ///
  /// Nothing is accumulated here: the worker already returns the complete
  /// stdout/stderr with its `done` message, so buffering every line a second
  /// time would only cost memory on a long encode.
  void handleLine(String stream, String line) {
    _logs.add(line);
    if (_command.reportProgress && stream != 'stderr') {
      final block = _parser.addLine(line);
      if (block != null) _progress.add(block);
    }
  }

  void _complete(
    int exitCode, {
    required String stdout,
    required String stderr,
  }) {
    _running = false;
    _wallClock.stop();
    final result = FfmpegResult(
      args: _command.args,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      wallClock: _wallClock.elapsed,
    );
    if (!_done.isCompleted) _done.complete(result);
    unawaited(_logs.close());
    unawaited(_progress.close());
  }

  /// A wasm FFmpeg cannot be signalled: the only way to stop it is to tear the
  /// worker down, which the bridge does. The run then reports a synthetic
  /// non-zero exit code because no real status can be observed.
  @override
  Future<bool> suspend() async => false;

  @override
  Future<bool> resume() async => false;

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    _running = false;
    onCancel();
    _complete(-2, stdout: '', stderr: 'cancelled');
  }
}

/// Entry point used by the conditional import in `ffmpeg.dart`.
FfmpegBackend createPlatformFfmpegBackend() => WebFfmpegBackend();
