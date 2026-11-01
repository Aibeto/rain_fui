/// Which encoders the FFmpeg binary in use can actually run.
///
/// The shipped build is a native-only build, while a distribution FFmpeg on
/// the same machine may carry libx264, libaom or the hardware encoders. The
/// table in `src/media` describes both families, so this probe decides what the
/// pickers show instead of guessing from the build that was bundled.
library;

import '../src/media/codec_spec.dart';
import '../src/media/generated/baseline_encoders.dart';
import '../src/media/generated/platform_baselines.dart';
import 'platform_key.dart';
import 'encoder_probe_stub.dart'
    if (dart.library.io) 'encoder_probe_io.dart'
    as probe;

/// Result of asking FFmpeg for its encoder list.
class EncoderAvailability {
  const EncoderAvailability({
    required this.names,
    required this.probed,
    this.error,
  });

  /// Encoder names (`-c:v` / `-c:a` values) the binary reports.
  final Set<String> names;

  /// True when [names] came from the binary, false when it is the baseline.
  final bool probed;

  /// Why the probe gave up, when it did.
  final String? error;

  /// What to use when the probe cannot run at all: only encoders the shipped
  /// build for this platform is known to contain.
  ///
  /// The list comes from the build itself (`config_components.h`), so the
  /// Android fallback still offers the MediaCodec encoders instead of the
  /// Linux list.
  static EncoderAvailability get baseline => EncoderAvailability(
    names: baselineNamesForCurrentPlatform,
    probed: false,
  );

  /// Encoders compiled into the shipped binary for the running platform.
  /// Baseline for an explicit platform key (`linux`, `windows`, `android`,
  /// `web`). Used by `tool/check_catalog.dart`, which runs on one machine but
  /// has to check every shipped build.
  static EncoderAvailability baselineForPlatform(String key) =>
      EncoderAvailability(
        names: kPlatformBaselineEncoders[key] ?? kBaselineEncoderNames,
        probed: false,
      );

  static Set<String> get baselineNamesForCurrentPlatform =>
      kPlatformBaselineEncoders[baselinePlatformKey()] ?? kBaselineEncoderNames;

  bool allows(CodecSpec spec) => names.contains(spec.encoder);

  /// Asks the resolved FFmpeg, falling back to [baseline].
  ///
  /// [androidNativeLibraryDir] comes from the platform side; the probe itself
  /// stays free of Flutter imports so it can also run under a plain Dart VM.
  static Future<EncoderAvailability> load({String? androidNativeLibraryDir}) =>
      probe.probeEncoderAvailability(
        androidNativeLibraryDir: androidNativeLibraryDir,
      );
}
