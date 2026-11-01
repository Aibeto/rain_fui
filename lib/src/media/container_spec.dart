/// A container (muxer) the encode form can write, with the streams it accepts.
library;

import 'option_spec.dart';

/// One selectable output container.
class ContainerSpec {
  const ContainerSpec({
    required this.id,
    required this.muxer,
    required this.name,
    required this.extension,
    required this.videoCodecs,
    required this.audioCodecs,
    this.options = const <OptionSpec>[],
    this.audioOnly = false,
  });

  /// Stable identifier used by the form state.
  final String id;

  /// Value passed to `-f`; empty means "let FFmpeg infer it from the file name".
  final String muxer;

  /// Display name such as `MP4`.
  final String name;

  /// File extension appended to the output name.
  final String extension;

  /// Ids of the video codecs this container can hold. Empty means video-only
  /// containers that take anything the encoder produces.
  final Set<String> videoCodecs;

  /// Ids of the audio codecs this container can hold.
  final Set<String> audioCodecs;

  /// Muxer options such as `-movflags`.
  final List<OptionSpec> options;

  /// True for containers that carry sound only (`mp3`, `flac`, `wav`, …).
  final bool audioOnly;

  /// Whether [codecId] can be muxed here.
  bool acceptsVideo(String codecId) => videoCodecs.contains(codecId);

  /// Whether [codecId] can be muxed here.
  bool acceptsAudio(String codecId) => audioCodecs.contains(codecId);

  /// Options shown directly under the picker.
  List<OptionSpec> get basicOptions =>
      options.where((OptionSpec o) => !o.advanced).toList(growable: false);

  /// Options hidden behind "more options".
  List<OptionSpec> get advancedOptions =>
      options.where((OptionSpec o) => o.advanced).toList(growable: false);
}
