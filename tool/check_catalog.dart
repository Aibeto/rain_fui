// ignore_for_file: avoid_print

/// Sanity-check the generated capability tables without running the app.
///
/// The tables describe every encoder FFmpeg can be built with; which ones the
/// form shows depends on the probe in `EncoderAvailability`. This script asks
/// the Dart side a handful of questions whose answers are known from the
/// probes, for both a native-only build and a distribution build.
///
///     dart run tool/check_catalog.dart
library;

import 'package:rain_fui/src/media/capabilities.dart';
import 'package:rain_fui/src/media/codec_ids.dart';
import 'package:rain_fui/src/media/codec_spec.dart';
import 'package:rain_fui/src/media/container_spec.dart';
import 'package:rain_fui/src/media/media_kind.dart';
import 'package:rain_fui/src/media/generated/baseline_encoders.dart';
import 'package:rain_fui/services/encoder_availability.dart';

int failures = 0;

void check(bool condition, String what) {
  if (!condition) {
    failures++;
    print('FAIL $what');
  }
}

bool offersVideo(String encoder) =>
    MediaCapabilities.videoCodecs.any((CodecSpec c) => c.encoder == encoder);

bool offersAudio(String encoder) =>
    MediaCapabilities.audioCodecs.any((CodecSpec c) => c.encoder == encoder);

Set<String> containerNames(MediaKind kind, String codecId) =>
    MediaCapabilities.containersFor(
      kind: kind,
      videoCodecId: kind == MediaKind.audio ? null : codecId,
      audioCodecId: kind == MediaKind.audio ? codecId : null,
    ).map((ContainerSpec c) => c.id).toSet();

void main() {
  // 1. The bundled, native-only build.
  MediaCapabilities.useAvailability(EncoderAvailability.baseline);
  print(
    'baseline: ${MediaCapabilities.videoCodecs.length} video, '
    '${MediaCapabilities.audioCodecs.length} audio, '
    '${MediaCapabilities.containers.length} containers',
  );
  check(offersVideo('mpeg4'), 'baseline offers mpeg4');
  check(offersVideo('ffv1'), 'baseline offers ffv1');
  check(offersAudio('aac'), 'baseline offers aac');
  check(offersAudio('opus'), 'baseline offers opus');
  check(!offersVideo('libx264'), 'baseline hides libx264');
  check(!offersVideo('av1_nvenc'), 'baseline hides av1_nvenc');
  check(offersVideo('prores_ks'), 'baseline offers prores_ks');

  // 2. A distribution build: the lib* and hardware encoders are there.
  final Set<String> full = <String>{
    ...kBaselineEncoderNames,
    'libx264',
    'libx265',
    'libaom-av1',
    'libsvtav1',
    'libvpx-vp9',
    'av1_nvenc',
    'h264_nvenc',
    'hevc_vaapi',
    'h264_qsv',
    'libopus',
    'libmp3lame',
    'libvorbis',
  };
  MediaCapabilities.useAvailability(
    EncoderAvailability(names: full, probed: true),
  );
  print(
    'distribution: ${MediaCapabilities.videoCodecs.length} video, '
    '${MediaCapabilities.audioCodecs.length} audio',
  );
  check(offersVideo('libx264'), 'distribution offers libx264');
  check(offersVideo('libaom-av1'), 'distribution offers libaom-av1');
  check(offersVideo('av1_nvenc'), 'distribution offers av1_nvenc');
  check(offersAudio('libopus'), 'distribution offers libopus');

  // 3. Codec ids, not encoder names, decide container compatibility.
  final CodecSpec libx264 = MediaCapabilities.videoCodecs.firstWhere(
    (CodecSpec c) => c.encoder == 'libx264',
  );
  final CodecSpec av1nvenc = MediaCapabilities.videoCodecs.firstWhere(
    (CodecSpec c) => c.encoder == 'av1_nvenc',
  );
  final CodecSpec libopus = MediaCapabilities.audioCodecs.firstWhere(
    (CodecSpec c) => c.encoder == 'libopus',
  );
  check(codecIdOf(libx264) == 'h264', 'libx264 reports codec h264');
  check(codecIdOf(av1nvenc) == 'av1', 'av1_nvenc reports codec av1');
  check(codecIdOf(libopus) == 'opus', 'libopus reports codec opus');

  final Set<String> holders = containerNames(MediaKind.video, libx264.id);
  check(holders.contains('mp4'), 'mp4 accepts libx264');
  check(!holders.contains('webm'), 'webm rejects libx264');
  check(!holders.contains('gif'), 'gif rejects libx264');
  check(
    containerNames(MediaKind.video, av1nvenc.id).contains('webm'),
    'webm accepts av1',
  );
  final Set<String> opusContainers = containerNames(
    MediaKind.audio,
    libopus.id,
  );
  check(opusContainers.contains('webm'), 'webm accepts opus');
  check(!opusContainers.contains('flac'), 'flac rejects opus');
  check(opusContainers.contains('opus'), 'the opus container accepts opus');

  print(failures == 0 ? 'catalog ok' : '$failures failure(s)');
  if (failures != 0) {
    throw StateError('$failures catalog check(s) failed');
  }
}
