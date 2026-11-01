/// Lookups over the static encoder / container table.
///
/// The table itself lives in `capabilities_data.dart` and mirrors what the
/// bundled FFmpeg build can actually do (see docs/ffmpeg-capabilities.md).
library;

import 'capabilities_data.dart';
import 'codec_spec.dart';
import 'container_spec.dart';
import 'media_kind.dart';

/// Query helpers over [kVideoCodecs], [kAudioCodecs] and [kContainers].
abstract final class MediaCapabilities {
  /// Every video encoder the form offers, in display order.
  static List<CodecSpec> get videoCodecs => kVideoCodecs;

  /// Every audio encoder the form offers, in display order.
  static List<CodecSpec> get audioCodecs => kAudioCodecs;

  /// Every container the form offers, in display order.
  static List<ContainerSpec> get containers => kContainers;

  /// Looks up a video encoder by id, or null.
  static CodecSpec? videoCodec(String? id) {
    if (id == null) {
      return null;
    }
    for (final CodecSpec codec in kVideoCodecs) {
      if (codec.id == id) {
        return codec;
      }
    }
    return null;
  }

  /// Looks up an audio encoder by id, or null.
  static CodecSpec? audioCodec(String? id) {
    if (id == null) {
      return null;
    }
    for (final CodecSpec codec in kAudioCodecs) {
      if (codec.id == id) {
        return codec;
      }
    }
    return null;
  }

  /// Looks up a container by id, or null.
  static ContainerSpec? container(String? id) {
    if (id == null) {
      return null;
    }
    for (final ContainerSpec container in kContainers) {
      if (container.id == id) {
        return container;
      }
    }
    return null;
  }

  /// Video encoders [container] can hold.
  static List<CodecSpec> videoCodecsFor(ContainerSpec container) => kVideoCodecs
      .where((CodecSpec codec) => container.acceptsVideo(codec.id))
      .toList(growable: false);

  /// Audio encoders [container] can hold.
  static List<CodecSpec> audioCodecsFor(ContainerSpec container) => kAudioCodecs
      .where((CodecSpec codec) => container.acceptsAudio(codec.id))
      .toList(growable: false);

  /// Containers that can hold the given selection.
  ///
  /// Passing null for a stream means "this file has no such stream".
  static List<ContainerSpec> containersFor({
    required MediaKind kind,
    String? videoCodecId,
    String? audioCodecId,
  }) {
    return kContainers
        .where((ContainerSpec container) {
          // The container has to be able to carry what the source holds. A
          // video-only muxer cannot take an audio file, and a pure audio
          // container silently drops the picture.
          switch (kind) {
            case MediaKind.video:
            case MediaKind.image:
              if (container.videoCodecs.isEmpty) {
                return false;
              }
            case MediaKind.audio:
              if (container.audioCodecs.isEmpty) {
                return false;
              }
            case MediaKind.unknown:
              break;
          }
          if (videoCodecId != null && !container.acceptsVideo(videoCodecId)) {
            return false;
          }
          if (audioCodecId != null && !container.acceptsAudio(audioCodecId)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }
}
