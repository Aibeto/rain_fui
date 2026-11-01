import 'ffmpeg_api.dart';

/// Fallback backend for compilers that provide neither `dart:io` nor
/// `dart:js_interop` (no such target exists today, but conditional imports need
/// a default branch).
class UnsupportedFfmpegBackend extends FfmpegBackend {
  @override
  String get platform => 'unsupported';

  @override
  bool get isAvailable => false;

  @override
  String? get unavailableReason => 'This platform has no FFmpeg backend.';

  @override
  String get executableDescription => 'not found';

  @override
  Future<void> initialize() async {}

  @override
  Future<String> version() async =>
      throw FfmpegNotFoundException(unavailableReason ?? 'Unsupported');

  @override
  Future<FfmpegTask> run(FfmpegCommand command) async =>
      throw FfmpegNotFoundException(unavailableReason ?? 'Unsupported');

  @override
  Future<void> dispose() async {}
}

FfmpegBackend createPlatformFfmpegBackend() => UnsupportedFfmpegBackend();
