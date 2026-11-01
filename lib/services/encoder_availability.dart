/// Which encoders the FFmpeg binary in use can actually run.
///
/// The shipped build is a native-only build, while a distribution FFmpeg on
/// the same machine may carry libx264, libaom or the hardware encoders. The
/// table in `src/media` describes both families, so this probe decides what the
/// pickers show instead of guessing from the build that was bundled.
library;

import '../src/media/codec_spec.dart';
import '../src/media/generated/baseline_encoders.dart';
import 'encoder_probe_stub.dart'
    if (dart.library.io) 'encoder_probe_io.dart'
    as probe;

/// Result of asking FFmpeg for its encoder list.
class EncoderAvailability {
  const EncoderAvailability({required this.names, required this.probed});

  /// Encoder names (`-c:v` / `-c:a` values) the binary reports.
  final Set<String> names;

  /// True when [names] came from the binary, false when it is the baseline.
  final bool probed;

  /// What to use when the probe cannot run at all: only encoders the bundled
  /// build is known to contain.
  static const EncoderAvailability baseline = EncoderAvailability(
    names: kBaselineEncoderNames,
    probed: false,
  );

  bool allows(CodecSpec spec) => names.contains(spec.encoder);

  /// Asks the resolved FFmpeg, falling back to [baseline].
  static Future<EncoderAvailability> load() => probe.probeEncoderAvailability();
}
