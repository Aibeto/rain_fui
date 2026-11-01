/// Mapping between an encoder name and the codec id containers care about.
///
/// FFmpeg separates the two: `libx264`, `h264_nvenc` and `h264_qsv` all produce
/// `h264`, and a muxer decides what it accepts by codec id, not by encoder
/// name. The table comes from the generated facts, so an encoder the generator
/// never saw falls back to its own name, which is correct for the native ones.
library;

import 'codec_spec.dart';
import 'generated/encoder_facts.dart';

/// Codec id produced by [encoder].
String codecIdOfEncoder(String encoder) => kEncoderCodecIds[encoder] ?? encoder;

/// Codec id produced by [spec].
String codecIdOf(CodecSpec spec) => codecIdOfEncoder(spec.encoder);
