/// A codec the encode form can select, paired with the encoder FFmpeg uses for
/// it and the options that encoder actually understands.
library;

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

  /// Options hidden behind "more options".
  List<OptionSpec> get advancedOptions =>
      options.where((OptionSpec o) => o.advanced).toList(growable: false);
}

/// Codec id used when a stream is dropped from the output.
const String kNoCodec = 'none';

/// Id of the stream-copy pseudo codec (`-c:v copy`).
const String kCopyCodec = 'copy';
