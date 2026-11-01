/// A codec the encode form can select, paired with the encoder FFmpeg uses for
/// it and the options that encoder actually understands.
library;

import '../../i18n/i18n_keys.dart';
import 'media_kind.dart';
import 'option_spec.dart';

/// One selectable stream encoder.
class CodecSpec {
  const CodecSpec({
    required this.id,
    required this.encoder,
    required this.name,
    required this.kind,
    this.pixelFormats = const <String>[],
    this.options = const <OptionSpec>[],
  });

  /// Stable identifier used by the form state and by container tables.
  final String id;

  /// Value passed to `-c:v` / `-c:a`.
  final String encoder;

  /// Display name. Proper nouns such as `H.264` are not translated; entries
  /// that need words use [labelKey].
  final String name;

  /// Whether this is a video or an audio encoder.
  final MediaKind kind;

  /// Pixel formats the encoder accepts, most common first. Empty means the
  /// encoder is not picky and the container decides.
  final List<String> pixelFormats;

  /// Everything this encoder exposes, in display order.
  final List<OptionSpec> options;

  /// Options shown directly under the picker.
  List<OptionSpec> get basicOptions =>
      options.where((OptionSpec o) => !o.advanced).toList(growable: false);

  /// Dropdown for `-pix_fmt`, built from the formats this encoder accepts.
  ///
  /// Building it per encoder matters: the shared list used to offer yuv444p to
  /// mpeg4, which only accepts yuv420p, so FFmpeg silently substituted the
  /// format instead of failing. Encoders with a very long list (FFV1, JPEG2000)
  /// are skipped because the picker would be unusable; their formats can still
  /// be typed into the custom-arguments box.
  OptionSpec? get pixelFormatOption {
    if (pixelFormats.length < 2 || pixelFormats.length > 16) {
      return null;
    }
    return ChoiceOption(
      flag: '-pix_fmt',
      labelKey: I18nKey.optPixelFormat,
      advanced: true,
      choices: <OptionChoice>[
        for (final String format in pixelFormats) OptionChoice(format),
      ],
    );
  }

  /// Options hidden behind "more options".
  List<OptionSpec> get advancedOptions =>
      options.where((OptionSpec o) => o.advanced).toList(growable: false);
}

/// Codec id used when a stream is dropped from the output.
const String kNoCodec = 'none';

/// Id of the stream-copy pseudo codec (`-c:v copy`).
const String kCopyCodec = 'copy';
