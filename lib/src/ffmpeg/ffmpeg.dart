/// Public entry point for the FFmpeg integration.
///
/// Import this library, call [createFfmpegBackend], and the conditional import
/// below picks the right implementation for the compilation target:
///
/// * `dart:io` targets (Linux, Windows, macOS, Android) → native process.
/// * `dart:js_interop` targets (web) → WebAssembly in a Web Worker.
library;

import 'ffmpeg_api.dart';
import 'ffmpeg_unsupported.dart'
    if (dart.library.io) 'ffmpeg_io.dart'
    if (dart.library.js_interop) 'ffmpeg_web.dart'
    as platform;

export 'ffmpeg_api.dart';

/// Creates the backend for the current platform.
///
/// The returned object is cheap: nothing is located or loaded until
/// [FfmpegBackend.initialize] runs.
FfmpegBackend createFfmpegBackend() => platform.createPlatformFfmpegBackend();
