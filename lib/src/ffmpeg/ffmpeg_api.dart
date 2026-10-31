/// Platform-agnostic FFmpeg API.
///
/// Nothing in this library imports `dart:io` or `dart:js_interop`; the concrete
/// backends in `ffmpeg_io.dart` / `ffmpeg_web.dart` do, and `ffmpeg.dart` picks
/// one at compile time with a conditional import.
library;

import 'dart:async';

/// Thrown when FFmpeg cannot be located, executed, or returns a failure.
class FfmpegException implements Exception {
  FfmpegException(this.message, {this.exitCode, this.stderr, this.cause});

  final String message;
  final int? exitCode;
  final String? stderr;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('FfmpegException: $message');
    if (exitCode != null) buffer.write(' (exit code $exitCode)');
    if (cause != null) buffer.write('\nCaused by: $cause');
    return buffer.toString();
  }
}

/// Thrown when no usable `ffmpeg` executable/wasm core could be found.
class FfmpegNotFoundException extends FfmpegException {
  FfmpegNotFoundException(super.message, {super.cause});

  @override
  String toString() => 'FfmpegNotFoundException: $message';
}

/// The result of a finished FFmpeg invocation.
class FfmpegResult {
  const FfmpegResult({
    required this.args,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.wallClock,
  });

  /// Arguments as passed to the backend, without the injected global flags.
  final List<String> args;
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration wallClock;

  bool get succeeded => exitCode == 0;

  /// Throws [FfmpegException] when the exit code is not zero.
  FfmpegResult ensureSucceeded() {
    if (succeeded) return this;
    final tail = stderr.trim().split('\n');
    throw FfmpegException(
      'ffmpeg exited with code $exitCode',
      exitCode: exitCode,
      stderr: tail.length > 8 ? tail.sublist(tail.length - 8).join('\n') : stderr,
    );
  }

  @override
  String toString() => 'FfmpegResult(exitCode: $exitCode, wallClock: $wallClock)';
}

/// One `-progress` block emitted by FFmpeg, e.g.
///
/// ```
/// frame=42
/// fps=25.0
/// out_time_us=1680000
/// speed=1.02x
/// progress=continue
/// ```
class FfmpegProgress {
  const FfmpegProgress(this.raw);

  final Map<String, String> raw;

  int? get frame => _asInt(raw['frame']);
  double? get fps => _asDouble(raw['fps']);
  int? get totalSize => _asInt(raw['total_size']);
  /// Bitrate in kbit/s. FFmpeg writes `512.0kbits/s`, so the unit is stripped.
  int? get bitrateKbps => _leadingDouble(raw['bitrate'])?.round();

  /// Playback position of the encoded output.
  Duration? get outTime {
    final micros = _asInt(raw['out_time_us']) ?? _asInt(raw['out_time_ms']);
    if (micros != null) return Duration(microseconds: micros);
    return parseFfmpegTimestamp(raw['out_time']);
  }

  /// Encoding speed relative to real time (`1.5x` → `1.5`).
  double? get speed {
    final value = raw['speed'];
    if (value == null) return null;
    return _asDouble(value.endsWith('x') ? value.substring(0, value.length - 1) : value);
  }

  bool get isFinal => raw['progress'] == 'end';

  @override
  String toString() => 'FfmpegProgress(outTime: $outTime, frame: $frame, fps: $fps, speed: $speed)';

  static int? _asInt(String? value) => value == null ? null : int.tryParse(value.trim());

  /// Parses the leading number of a value, ignoring any trailing unit.
  static double? _leadingDouble(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^[-+]?\d+(?:\.\d+)?').firstMatch(value.trim());
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  static double? _asDouble(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'N/A') return null;
    return double.tryParse(trimmed);
  }
}

/// Parses `HH:MM:SS.micros` (FFmpeg's `out_time`) into a [Duration].
Duration? parseFfmpegTimestamp(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d+):(\d{2}):(\d{2}(?:\.\d+)?)$').firstMatch(value.trim());
  if (match == null) return null;
  final micros = ((double.parse(match.group(3)!)) * Duration.microsecondsPerSecond).round();
  return Duration(
    hours: int.parse(match.group(1)!),
    minutes: int.parse(match.group(2)!),
    microseconds: micros,
  );
}

/// Stateful parser for FFmpeg's `-progress pipe:1` output.
///
/// Feed it one line at a time; it returns an [FfmpegProgress] each time a
/// complete block (terminated by the `progress=` key) has been accumulated.
class FfmpegProgressParser {
  final Map<String, String> _pending = <String, String>{};

  FfmpegProgress? addLine(String line) {
    final separator = line.indexOf('=');
    if (separator <= 0) return null;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    _pending[key] = value;
    if (key != 'progress') return null;
    final block = Map<String, String>.unmodifiable(_pending);
    _pending.clear();
    return FfmpegProgress(block);
  }
}

/// A single FFmpeg invocation.
class FfmpegCommand {
  FfmpegCommand(
    List<String> args, {
    this.reportProgress = true,
    this.allowStdin = false,
  }) : args = List<String>.unmodifiable(args) {
    if (args.isEmpty) {
      throw ArgumentError.value(args, 'args', 'ffmpeg needs at least one argument');
    }
  }

  /// Arguments the caller wants, e.g. `['-i', 'in.mp4', 'out.webm']`.
  final List<String> args;

  /// When true, `-progress pipe:1 -nostats` is injected and [FfmpegTask.progress]
  /// emits parsed progress blocks.
  ///
  /// Leave this false when FFmpeg's own stdout carries payload (e.g. a pipe
  /// output `-f mp4 -`), because progress would corrupt the media stream.
  final bool reportProgress;

  /// By default stdin is closed (`-nostdin`) so a GUI can never hang on input.
  final bool allowStdin;

  /// The full argv handed to the backend, with our injected global flags first.
  List<String> toArgv() {
    final injected = <String>['-hide_banner'];
    if (!allowStdin) injected.add('-nostdin');
    if (reportProgress) {
      if (!_hasFlag(args, '-progress')) {
        injected.addAll(const <String>['-nostats', '-progress', 'pipe:1']);
      }
    }
    return List<String>.unmodifiable(<String>[...injected, ...args]);
  }

  static bool _hasFlag(List<String> args, String flag) =>
      args.any((arg) => arg == flag || arg.startsWith('$flag='));
}

/// A running (or finished) FFmpeg invocation.
abstract interface class FfmpegTask {
  /// Human-readable log lines from both stdout and stderr.
  Stream<String> get logs;

  /// Parsed progress blocks; empty when [FfmpegCommand.reportProgress] is false.
  Stream<FfmpegProgress> get progress;

  /// Completes when the process/worker exits. Never completes with an error.
  Future<FfmpegResult> get done;

  bool get isRunning;

  /// True once [cancel] has been requested, even if the process has not exited
  /// yet. Useful for telling a user-initiated stop from a real failure.
  bool get wasCancelled;

  /// Terminates the run. Safe to call more than once.
  Future<void> cancel();
}

/// The platform-specific FFmpeg driver.
abstract class FfmpegBackend {
  /// Short platform tag, e.g. `linux`, `windows`, `android`, `web`.
  String get platform;

  /// Locates/verifies the FFmpeg build once. Idempotent, and called
  /// automatically by [version] and [run].
  Future<void> initialize();

  /// Whether a usable FFmpeg build was found. Meaningful after
  /// [initialize] has completed.
  bool get isAvailable;

  /// Why FFmpeg is unavailable, or null when it works. Useful for the UI.
  String? get unavailableReason;

  /// Absolute path of the binary, or `wasm (web)` for the web backend.
  String get executableDescription;

  /// First line of `ffmpeg -version` (cached after the first call).
  Future<String> version();

  /// Starts [command]; throws [FfmpegNotFoundException] when unavailable.
  Future<FfmpegTask> run(FfmpegCommand command);

  /// Releases cached resources (no-op for the io backend).
  Future<void> dispose();

  /// Web only: copies a file out of FFmpeg's in-memory filesystem into a
  /// browser download. Returns false on native platforms, where outputs are
  /// written to the real filesystem and no export step is needed.
  Future<bool> saveOutputFile(String virtualPath, {String? downloadName}) async => false;
}

/// Splits a command line into arguments, honouring quotes and escapes.
///
/// This is the inverse of `Process.run`'s argv joining, used so the UI can let
/// people type `-i "my video.mp4" -c:v libx264`.
///
/// * whitespace separates arguments,
/// * `'...'` and `"..."` group text (the quotes are removed),
/// * a backslash escapes the next character (outside single quotes).
///
/// Throws a [FormatException] for an unterminated quote.
List<String> splitCommandArgs(String input) {
  final args = <String>[];
  final current = StringBuffer();
  var hasContent = false;
  String? quote;

  void flush() {
    if (hasContent) {
      args.add(current.toString());
      current.clear();
      hasContent = false;
    }
  }

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else if (char == r'\' && quote == '"' && i + 1 < input.length) {
        current.write(input[++i]);
      } else {
        current.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      hasContent = true;
    } else if (char == r'\' && i + 1 < input.length) {
      current.write(input[++i]);
      hasContent = true;
    } else if (char.trim().isEmpty) {
      flush();
    } else {
      current.write(char);
      hasContent = true;
    }
  }

  if (quote != null) {
    throw FormatException('Unterminated $quote quote', input, input.length - 1);
  }
  flush();
  return List<String>.unmodifiable(args);
}

/// Preset argument lists used by the UI (and handy in tests).
abstract final class FfmpegPresets {
  /// Build information: always safe, no input files needed.
  static const List<String> version = <String>['-version'];

  /// Everything this build can encode.
  static const List<String> encoders = <String>['-encoders'];

  /// Demuxers/muxers, protocols.
  static const List<String> formats = <String>['-formats'];

  /// Runs a real filter graph and encode, discarding the output. Works on every
  /// platform (including web) because no file needs to exist.
  static const List<String> testSourceToNull = <String>[
    '-f', 'lavfi',
    '-i', 'testsrc2=duration=1:size=320x240:rate=25',
    '-f', 'null', '-',
  ];

  /// Encodes a generated test pattern + tone into a real MP4 file in the
  /// current directory. Uses only FFmpeg-native encoders (mpeg4/aac), so it
  /// works without external libraries.
  static const List<String> testSourceToMp4 = <String>[
    '-f', 'lavfi',
    '-i', 'testsrc2=duration=2:size=640x360:rate=25',
    '-f', 'lavfi',
    '-i', 'sine=duration=2',
    '-c:v', 'mpeg4',
    '-q:v', '5',
    '-c:a', 'aac',
    '-b:a', '96k',
    '-shortest',
    '-y',
    'rain_fui_sample.mp4',
  ];
}
