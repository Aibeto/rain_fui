/// Lookups over the static encoder / container table.
///
/// The table itself lives in `capabilities_data.dart` and mirrors what the
/// bundled FFmpeg build can actually do (see docs/ffmpeg-capabilities.md).
library;

import '../../services/encoder_availability.dart';
import 'capabilities_data.dart';
import 'codec_ids.dart';
import 'codec_spec.dart';
import 'container_spec.dart';
import 'media_kind.dart';

/// Query helpers over [kVideoCodecs], [kAudioCodecs] and [kContainers].
///
/// The tables describe every encoder FFmpeg can be built with. What the form
/// shows is filtered by [availability], which asks the binary in use, so a
/// native-only build never offers `libx264` and a distribution build does.
abstract final class MediaCapabilities {
  static EncoderAvailability _availability = EncoderAvailability.baseline;
  static List<CodecSpec>? _videoCache;
  static List<CodecSpec>? _audioCache;

  /// What the FFmpeg binary in use can run.
  static EncoderAvailability get availability => _availability;

  /// Installs a probe result. Passing null restores the bundled baseline.
  static void useAvailability(EncoderAvailability? availability) {
    _availability = availability ?? EncoderAvailability.baseline;
    _videoCache = null;
    _audioCache = null;
  }

  /// Every video encoder the form offers, in display order.
  static List<CodecSpec> get videoCodecs => _videoCache ??= kVideoCodecs
      .where(_availability.allows)
      .toList(growable: false);

  /// Every audio encoder the form offers, in display order.
  static List<CodecSpec> get audioCodecs => _audioCache ??= kAudioCodecs
      .where(_availability.allows)
      .toList(growable: false);

  /// Every container the form offers, in display order.
  static List<ContainerSpec> get containers => kContainers;

  /// Looks up a video encoder by id, or null.
  static CodecSpec? videoCodec(String? id) {
    if (id == null) {
      return null;
    }
    for (final CodecSpec codec in videoCodecs) {
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
    for (final CodecSpec codec in audioCodecs) {
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
  static List<CodecSpec> videoCodecsFor(ContainerSpec container) => videoCodecs
      .where((CodecSpec codec) => container.acceptsVideo(codecIdOf(codec)))
      .toList(growable: false);

  /// Audio encoders [container] can hold.
  static List<CodecSpec> audioCodecsFor(ContainerSpec container) => audioCodecs
      .where((CodecSpec codec) => container.acceptsAudio(codecIdOf(codec)))
      .toList(growable: false);

  /// Containers that can hold the given selection.
  ///
  /// Passing null for a stream means "this file has no such stream".
  /// Extensions that hold a single still image.
  static const Set<String> _imageContainerExtensions = <String>{
    'png',
    'apng',
    'gif',
    'jpg',
    'jpeg',
    'bmp',
    'tiff',
  };

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
              // A still-image muxer would quietly write a single frame.
              if (container.videoCodecs.isEmpty ||
                  _imageContainerExtensions.contains(container.extension)) {
                return false;
              }
            case MediaKind.image:
              if (container.videoCodecs.isEmpty ||
                  !_imageContainerExtensions.contains(container.extension)) {
                return false;
              }
            case MediaKind.audio:
              if (container.audioCodecs.isEmpty) {
                return false;
              }
            case MediaKind.unknown:
              break;
          }
          final CodecSpec? video = videoCodec(videoCodecId);
          if (video != null && !container.acceptsVideo(codecIdOf(video))) {
            return false;
          }
          final CodecSpec? audio = audioCodec(audioCodecId);
          if (audio != null && !container.acceptsAudio(codecIdOf(audio))) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }
}
