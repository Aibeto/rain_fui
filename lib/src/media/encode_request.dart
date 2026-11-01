/// Everything needed to turn a form selection into one FFmpeg invocation.
library;

import 'codec_spec.dart';
import 'container_spec.dart';
import 'media_kind.dart';
import 'option_spec.dart';

/// One queued encode, frozen at the moment the user pressed Start.
class EncodeRequest {
  const EncodeRequest({
    required this.kind,
    required this.inputPath,
    required this.inputName,
    required this.outputPath,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    this.videoDecoder,
    this.audioDecoder,
    this.optionValues = const <String, String>{},
    this.customArgs = '',
  });

  /// Media category of the input.
  final MediaKind kind;

  /// Absolute path of the input, or null where the platform has no path (web).
  final String? inputPath;

  /// File name of the input, always present.
  final String inputName;

  /// Where the encode writes its result.
  final String outputPath;

  /// Target container.
  final ContainerSpec container;

  /// Selected video encoder, or null for "no video stream".
  final CodecSpec? videoCodec;

  /// Selected audio encoder, or null for "no audio stream".
  final CodecSpec? audioCodec;

  /// Forced input video decoder, or null to let FFmpeg detect it.
  final String? videoDecoder;

  /// Forced input audio decoder, or null to let FFmpeg detect it.
  final String? audioDecoder;

  /// Option flag to raw value, as edited in the form.
  final Map<String, String> optionValues;

  /// Free-form arguments appended verbatim before the output path.
  final String customArgs;

  /// All options that belong to the chosen encoder and container.
  List<OptionSpec> get activeOptions => <OptionSpec>[
    if (videoCodec != null) ...videoCodec!.options,
    if (audioCodec != null) ...audioCodec!.options,
    ...container.options,
  ];

  /// CLI arguments for [optionValues], in the order the specs declare.
  List<String> buildOptionArgs() {
    final List<String> args = <String>[];
    final Set<String> usedGroups = <String>{};
    for (final OptionSpec spec in activeOptions) {
      final String? value = optionValues[spec.flag] ?? spec.initialValue;
      final List<String> rendered = spec.render(value);
      final String? group = spec.exclusiveGroup;
      if (rendered.isEmpty || (group != null && usedGroups.contains(group))) {
        continue;
      }
      if (group != null) {
        usedGroups.add(group);
      }
      args.addAll(rendered);
    }
    return args;
  }
}

/// Splits a free-form argument string the way a shell would for simple cases.
///
/// Supports single quotes, double quotes and backslash escapes outside quotes,
/// which covers everything a user types into the custom field in practice.
List<String> splitCommandLine(String input) {
  final List<String> out = <String>[];
  final StringBuffer current = StringBuffer();
  bool hasToken = false;
  String? quote;
  for (int i = 0; i < input.length; i++) {
    final String ch = input[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else if (ch == r'\' && quote == '"' && i + 1 < input.length) {
        current.write(input[++i]);
      } else {
        current.write(ch);
      }
      hasToken = true;
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      hasToken = true;
      continue;
    }
    if (ch == r'\' && i + 1 < input.length) {
      current.write(input[++i]);
      hasToken = true;
      continue;
    }
    if (ch == ' ' || ch == '\t' || ch == '\n') {
      if (hasToken) {
        out.add(current.toString());
        current.clear();
        hasToken = false;
      }
      continue;
    }
    current.write(ch);
    hasToken = true;
  }
  if (hasToken) {
    out.add(current.toString());
  }
  return out;
}

/// Builds the full argument vector for [request].
///
/// The result starts after the binary: `ffmpeg <args...>`.
List<String> buildEncodeArgs(EncodeRequest request) {
  // Banner, stdin and progress flags are injected by FfmpegCommand itself.
  final List<String> args = <String>['-y'];
  // Input-side options must come before `-i` to affect the decoder.
  final String? videoDecoder = request.videoDecoder;
  if (videoDecoder != null && videoDecoder.isNotEmpty) {
    args.addAll(<String>['-c:v', videoDecoder]);
  }
  final String? audioDecoder = request.audioDecoder;
  if (audioDecoder != null && audioDecoder.isNotEmpty) {
    args.addAll(<String>['-c:a', audioDecoder]);
  }
  final String? inputPath = request.inputPath;
  if (inputPath != null && inputPath.isNotEmpty) {
    args.addAll(<String>['-i', inputPath]);
  } else {
    // Web builds have no host path; the bridge stages the file under its name.
    args.addAll(<String>['-i', request.inputName]);
  }

  final CodecSpec? video = request.videoCodec;
  if (video == null) {
    args.add('-vn');
  } else {
    args.addAll(<String>['-c:v', video.encoder]);
  }
  final CodecSpec? audio = request.audioCodec;
  if (audio == null) {
    args.add('-an');
  } else {
    args.addAll(<String>['-c:a', audio.encoder]);
  }

  args.addAll(request.buildOptionArgs());

  // A still image becomes a single frame unless the user said otherwise.
  if (request.kind == MediaKind.image) {
    args.addAll(<String>['-frames:v', '1']);
  }

  args.addAll(splitCommandLine(request.customArgs));

  final String muxer = request.container.muxer;
  if (muxer.isNotEmpty) {
    args.addAll(<String>['-f', muxer]);
  }
  args.add(request.outputPath);
  return args;
}
