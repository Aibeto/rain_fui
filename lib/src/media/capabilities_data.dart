/// The codec and container table this build of FFmpeg can actually use.
///
/// Every encoder named here is a native FFmpeg encoder: the bundled build runs
/// with `--disable-autodetect` and no `--enable-lib*` flag, so encoders that
/// live in external libraries (libx264, libx265, libvpx, libaom, libsvtav1,
/// libopus, libmp3lame, libvorbis, libwebp) are absent and must not be offered.
/// See docs/ffmpeg-capabilities.md for the source trail.
library;

import '../../i18n/i18n_keys.dart';
import 'codec_spec.dart';
import 'container_spec.dart';
import 'media_kind.dart';
import 'option_spec.dart';

// ---------------------------------------------------------------------------
// Shared option groups
// ---------------------------------------------------------------------------

/// Quality and rate control knobs almost every video encoder honours.
const List<OptionSpec> _videoRateOptions = <OptionSpec>[
  IntOption(
    flag: '-q:v',
    exclusiveGroup: 'rate',
    labelKey: I18nKey.optQualityScale,
    min: 1,
    max: 31,
  ),
  IntOption(
    flag: '-b:v',
    exclusiveGroup: 'rate',
    labelKey: I18nKey.optBitrateVideo,
    min: 1,
    unit: 'kbps',
    advanced: true,
  ),
  IntOption(
    flag: '-qmin',
    labelKey: I18nKey.optQuantMin,
    min: 1,
    max: 31,
    advanced: true,
  ),
  IntOption(
    flag: '-qmax',
    labelKey: I18nKey.optQuantMax,
    min: 1,
    max: 31,
    advanced: true,
  ),
  IntOption(
    flag: '-maxrate',
    exclusiveGroup: 'rate',
    labelKey: I18nKey.optMaxRate,
    min: 1,
    unit: 'kbps',
    advanced: true,
  ),
  IntOption(
    flag: '-bufsize',
    exclusiveGroup: 'rate',
    labelKey: I18nKey.optBufSize,
    min: 1,
    unit: 'kbps',
    advanced: true,
  ),
];

/// Structural knobs shared by the block-based video encoders.
const List<OptionSpec> _videoStructureOptions = <OptionSpec>[
  IntOption(flag: '-g', labelKey: I18nKey.optGopSize, min: 0, advanced: true),
  IntOption(
    flag: '-bf',
    labelKey: I18nKey.optBFrames,
    min: 0,
    max: 16,
    advanced: true,
  ),
  ChoiceOption(
    flag: '-pix_fmt',
    labelKey: I18nKey.optPixelFormat,
    advanced: true,
    choices: <OptionChoice>[
      OptionChoice('yuv420p'),
      OptionChoice('yuv422p'),
      OptionChoice('yuv444p'),
      OptionChoice('yuv420p10le'),
      OptionChoice('yuv422p10le'),
      OptionChoice('rgb24'),
      OptionChoice('rgba'),
      OptionChoice('gray'),
    ],
  ),
];

/// Threading is a codec-context field, not an encoder option, but it is the one
/// knob users reach for on a slow machine.
const OptionSpec _threadsOption = IntOption(
  flag: '-threads',
  labelKey: I18nKey.optThreads,
  min: 0,
  max: 64,
  advanced: true,
);

// ---------------------------------------------------------------------------
// Video encoders
// ---------------------------------------------------------------------------

/// Every video encoder the form offers.
final List<CodecSpec> kVideoCodecs = <CodecSpec>[
  CodecSpec(
    id: 'mpeg4',
    encoder: 'mpeg4',
    name: 'MPEG-4 Part 2',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ..._videoRateOptions,
      ChoiceOption(
        flag: '-profile:v',
        labelKey: I18nKey.optProfile,
        choices: const <OptionChoice>[
          OptionChoice('simple'),
          OptionChoice('advanced'),
        ],
      ),
      ChoiceOption(
        flag: '-mbd',
        labelKey: I18nKey.optMbDecision,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('simple'),
          OptionChoice('bits'),
          OptionChoice('rd'),
        ],
      ),
      IntOption(
        flag: '-trellis',
        labelKey: I18nKey.optTrellis,
        min: 0,
        max: 2,
        advanced: true,
      ),
      IntOption(
        flag: '-mv4',
        labelKey: I18nKey.optMvFourMotion,
        min: 0,
        max: 1,
        advanced: true,
      ),
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'mpeg2video',
    encoder: 'mpeg2video',
    name: 'MPEG-2',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ..._videoRateOptions,
      ChoiceOption(
        flag: '-profile:v',
        labelKey: I18nKey.optProfile,
        choices: const <OptionChoice>[
          OptionChoice('simple'),
          OptionChoice('main'),
          OptionChoice('high'),
          OptionChoice('422'),
        ],
      ),
      ChoiceOption(
        flag: '-level',
        labelKey: I18nKey.optLevel,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('low'),
          OptionChoice('main'),
          OptionChoice('high1440'),
          OptionChoice('high'),
        ],
      ),
      IntOption(
        flag: '-trellis',
        labelKey: I18nKey.optTrellis,
        min: 0,
        max: 2,
        advanced: true,
      ),
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'mpeg1video',
    encoder: 'mpeg1video',
    name: 'MPEG-1',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ..._videoRateOptions,
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'h263',
    encoder: 'h263',
    name: 'H.263',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ..._videoRateOptions,
      IntOption(
        flag: '-g',
        labelKey: I18nKey.optGopSize,
        min: 0,
        advanced: true,
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'mjpeg',
    encoder: 'mjpeg',
    name: 'Motion JPEG',
    kind: MediaKind.video,
    options: <OptionSpec>[
      IntOption(
        flag: '-q:v',
        exclusiveGroup: 'rate',
        labelKey: I18nKey.optQualityScale,
        min: 1,
        max: 31,
      ),
      IntOption(
        flag: '-huffman',
        labelKey: I18nKey.optHuffman,
        min: 0,
        max: 1,
        advanced: true,
      ),
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'ljpeg',
    encoder: 'ljpeg',
    name: 'Lossless JPEG',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-pix_fmt',
        labelKey: I18nKey.optPixelFormat,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('yuvj420p'),
          OptionChoice('yuvj422p'),
          OptionChoice('yuvj444p'),
          OptionChoice('bgr24'),
        ],
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'png',
    encoder: 'png',
    name: 'PNG',
    kind: MediaKind.video,
    options: <OptionSpec>[
      IntOption(
        flag: '-compression_level',
        labelKey: I18nKey.optCompressionLevel,
        min: 0,
        max: 9,
      ),
      IntOption(
        flag: '-pred',
        labelKey: I18nKey.optPrediction,
        min: 0,
        max: 5,
        advanced: true,
      ),
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'gif',
    encoder: 'gif',
    name: 'GIF',
    kind: MediaKind.video,
    options: <OptionSpec>[
      IntOption(
        flag: '-g',
        labelKey: I18nKey.optGopSize,
        min: 0,
        advanced: true,
      ),
      ChoiceOption(
        flag: '-pix_fmt',
        labelKey: I18nKey.optPixelFormat,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('rgb8'),
          OptionChoice('bgr8'),
        ],
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'ffv1',
    encoder: 'ffv1',
    name: 'FFV1',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-level',
        labelKey: I18nKey.optCodecLevel,
        choices: const <OptionChoice>[OptionChoice('1'), OptionChoice('3')],
      ),
      ChoiceOption(
        flag: '-coder',
        labelKey: I18nKey.optCoder,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('golomb'),
          OptionChoice('range_def'),
          OptionChoice('range_tab'),
        ],
      ),
      IntOption(
        flag: '-slices',
        labelKey: I18nKey.optSlices,
        min: 1,
        max: 60,
        advanced: true,
      ),
      IntOption(
        flag: '-slicecrc',
        labelKey: I18nKey.optSliceCrc,
        min: 0,
        max: 1,
        advanced: true,
      ),
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'huffyuv',
    encoder: 'huffyuv',
    name: 'HuffYUV',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-pred',
        labelKey: I18nKey.optPrediction,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('left'),
          OptionChoice('median'),
        ],
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'utvideo',
    encoder: 'utvideo',
    name: 'Ut Video',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-pred',
        labelKey: I18nKey.optPrediction,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('none'),
          OptionChoice('left'),
          OptionChoice('gradient'),
          OptionChoice('median'),
        ],
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'prores',
    encoder: 'prores',
    name: 'Apple ProRes',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-profile:v',
        labelKey: I18nKey.optProfile,
        choices: const <OptionChoice>[
          OptionChoice('proxy'),
          OptionChoice('lt'),
          OptionChoice('standard'),
          OptionChoice('hq'),
          OptionChoice('4444'),
          OptionChoice('4444xq'),
        ],
      ),
      TextOption(flag: '-vendor', labelKey: I18nKey.optVendor, advanced: true),
      IntOption(
        flag: '-bits_per_mb',
        labelKey: I18nKey.optBitsPerMb,
        min: 1,
        advanced: true,
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'dnxhd',
    encoder: 'dnxhd',
    name: 'DNxHD / DNxHR',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-profile:v',
        labelKey: I18nKey.optProfile,
        choices: const <OptionChoice>[
          OptionChoice('dnxhd'),
          OptionChoice('dnxhr_lb'),
          OptionChoice('dnxhr_sq'),
          OptionChoice('dnxhr_hq'),
          OptionChoice('dnxhr_hqx'),
          OptionChoice('dnxhr_444'),
        ],
      ),
      IntOption(
        flag: '-b:v',
        labelKey: I18nKey.optBitrateVideo,
        min: 1,
        unit: 'kbps',
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'dvvideo',
    encoder: 'dvvideo',
    name: 'DV',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-pix_fmt',
        labelKey: I18nKey.optPixelFormat,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('yuv411p'),
          OptionChoice('yuv420p'),
          OptionChoice('yuv422p'),
        ],
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'rawvideo',
    encoder: 'rawvideo',
    name: 'Raw video',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-pix_fmt',
        labelKey: I18nKey.optPixelFormat,
        choices: const <OptionChoice>[
          OptionChoice('yuv420p'),
          OptionChoice('yuv422p'),
          OptionChoice('yuv444p'),
          OptionChoice('rgb24'),
          OptionChoice('rgba'),
          OptionChoice('gray'),
        ],
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'flv',
    encoder: 'flv',
    name: 'FLV1',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ..._videoRateOptions,
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'wmv2',
    encoder: 'wmv2',
    name: 'Windows Media Video 8',
    kind: MediaKind.video,
    options: <OptionSpec>[
      IntOption(
        flag: '-b:v',
        labelKey: I18nKey.optBitrateVideo,
        min: 1,
        unit: 'kbps',
      ),
      ..._videoStructureOptions,
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'qtrle',
    encoder: 'qtrle',
    name: 'QuickTime Animation',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-pix_fmt',
        labelKey: I18nKey.optPixelFormat,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('rgb24'),
          OptionChoice('argb'),
          OptionChoice('gray'),
        ],
      ),
      _threadsOption,
    ],
  ),
  CodecSpec(
    id: 'zmbv',
    encoder: 'zmbv',
    name: 'Zip Motion Blocks',
    kind: MediaKind.video,
    options: <OptionSpec>[
      ChoiceOption(
        flag: '-pix_fmt',
        labelKey: I18nKey.optPixelFormat,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('pal8'),
          OptionChoice('rgb555le'),
          OptionChoice('rgb24'),
        ],
      ),
      _threadsOption,
    ],
  ),
];

// ---------------------------------------------------------------------------
// Audio encoders
// ---------------------------------------------------------------------------

/// Every audio encoder the form offers.
final List<CodecSpec> kAudioCodecs = <CodecSpec>[
  CodecSpec(
    id: 'aac',
    encoder: 'aac',
    name: 'AAC',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-b:a',
        exclusiveGroup: 'audioRate',
        labelKey: I18nKey.optBitrateAudio,
        min: 8,
        unit: 'kbps',
      ),
      ChoiceOption(
        flag: '-aac_coder',
        labelKey: I18nKey.optCoder,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('twoloop'),
          OptionChoice('fast'),
          OptionChoice('anmr'),
        ],
      ),
      IntOption(
        flag: '-cutoff',
        labelKey: I18nKey.optCutoff,
        min: 1000,
        max: 96000,
        advanced: true,
      ),
      IntOption(
        flag: '-ar',
        labelKey: I18nKey.optSampleRate,
        min: 7350,
        max: 96000,
        advanced: true,
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 8,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'ac3',
    encoder: 'ac3',
    name: 'Dolby Digital (AC-3)',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-b:a',
        labelKey: I18nKey.optBitrateAudio,
        min: 32,
        max: 640,
        unit: 'kbps',
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 6,
        advanced: true,
      ),
      IntOption(
        flag: '-dialnorm',
        labelKey: I18nKey.optDialNorm,
        min: -31,
        max: -1,
        advanced: true,
      ),
      IntOption(
        flag: '-dsur_mode',
        labelKey: I18nKey.optDolbySurround,
        min: 0,
        max: 2,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'eac3',
    encoder: 'eac3',
    name: 'Dolby Digital Plus (E-AC-3)',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-b:a',
        labelKey: I18nKey.optBitrateAudio,
        min: 32,
        max: 6144,
        unit: 'kbps',
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 8,
        advanced: true,
      ),
      IntOption(
        flag: '-dialnorm',
        labelKey: I18nKey.optDialNorm,
        min: -31,
        max: -1,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'mp2',
    encoder: 'mp2',
    name: 'MPEG-1 Layer II',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-b:a',
        labelKey: I18nKey.optBitrateAudio,
        min: 32,
        max: 384,
        unit: 'kbps',
      ),
      IntOption(
        flag: '-ar',
        labelKey: I18nKey.optSampleRate,
        min: 32000,
        max: 48000,
        advanced: true,
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 2,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'flac',
    encoder: 'flac',
    name: 'FLAC',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-compression_level',
        labelKey: I18nKey.optCompressionLevel,
        min: 0,
        max: 12,
      ),
      IntOption(
        flag: '-ar',
        labelKey: I18nKey.optSampleRate,
        min: 8000,
        max: 192000,
        advanced: true,
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 8,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'alac',
    encoder: 'alac',
    name: 'Apple Lossless (ALAC)',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-ar',
        labelKey: I18nKey.optSampleRate,
        min: 8000,
        max: 384000,
        advanced: true,
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 8,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'opus',
    encoder: 'opus',
    name: 'Opus',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-b:a',
        labelKey: I18nKey.optBitrateAudio,
        min: 6,
        max: 512,
        unit: 'kbps',
      ),
      ChoiceOption(
        flag: '-application',
        labelKey: I18nKey.optApplication,
        advanced: true,
        choices: const <OptionChoice>[
          OptionChoice('voip'),
          OptionChoice('audio'),
          OptionChoice('lowdelay'),
        ],
      ),
      IntOption(
        flag: '-frame_duration',
        labelKey: I18nKey.optFrameDuration,
        min: 2,
        max: 120,
        advanced: true,
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 2,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'vorbis',
    encoder: 'vorbis',
    name: 'Vorbis (experimental)',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-q:a',
        exclusiveGroup: 'audioRate',
        labelKey: I18nKey.optQualityScaleAudio,
        min: -1,
        max: 10,
      ),
      IntOption(
        flag: '-ac',
        labelKey: I18nKey.optChannels,
        min: 1,
        max: 8,
        advanced: true,
      ),
    ],
  ),
  CodecSpec(
    id: 'pcm_s16le',
    encoder: 'pcm_s16le',
    name: 'PCM 16-bit',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-ar',
        labelKey: I18nKey.optSampleRate,
        min: 8000,
        max: 192000,
      ),
      IntOption(flag: '-ac', labelKey: I18nKey.optChannels, min: 1, max: 8),
    ],
  ),
  CodecSpec(
    id: 'pcm_s24le',
    encoder: 'pcm_s24le',
    name: 'PCM 24-bit',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-ar',
        labelKey: I18nKey.optSampleRate,
        min: 8000,
        max: 192000,
      ),
      IntOption(flag: '-ac', labelKey: I18nKey.optChannels, min: 1, max: 8),
    ],
  ),
  CodecSpec(
    id: 'pcm_f32le',
    encoder: 'pcm_f32le',
    name: 'PCM 32-bit float',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-ar',
        labelKey: I18nKey.optSampleRate,
        min: 8000,
        max: 192000,
      ),
      IntOption(flag: '-ac', labelKey: I18nKey.optChannels, min: 1, max: 8),
    ],
  ),
  CodecSpec(
    id: 'truehd',
    encoder: 'truehd',
    name: 'Dolby TrueHD',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(flag: '-ac', labelKey: I18nKey.optChannels, min: 1, max: 8),
    ],
  ),
  CodecSpec(
    id: 'wavpack',
    encoder: 'wavpack',
    name: 'WavPack',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-compression_level',
        labelKey: I18nKey.optCompressionLevel,
        min: 0,
        max: 8,
      ),
    ],
  ),
  CodecSpec(
    id: 'tta',
    encoder: 'tta',
    name: 'TTA',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-compression_level',
        labelKey: I18nKey.optCompressionLevel,
        min: 0,
        max: 8,
      ),
    ],
  ),
  CodecSpec(
    id: 'wmav2',
    encoder: 'wmav2',
    name: 'Windows Media Audio 2',
    kind: MediaKind.audio,
    options: <OptionSpec>[
      IntOption(
        flag: '-b:a',
        labelKey: I18nKey.optBitrateAudio,
        min: 16,
        max: 320,
        unit: 'kbps',
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Containers
// ---------------------------------------------------------------------------

/// Muxer-level options shared by the ISO base media family.
const List<OptionSpec> _movFlags = <OptionSpec>[
  ChoiceOption(
    flag: '-movflags',
    labelKey: I18nKey.optMovFlags,
    choices: <OptionChoice>[
      OptionChoice('+faststart', labelKey: I18nKey.optMovFastStart),
      OptionChoice(
        '+frag_keyframe+empty_moov',
        labelKey: I18nKey.optMovFragmented,
      ),
      OptionChoice('+use_metadata_tags', labelKey: I18nKey.optMovMetadataTags),
    ],
  ),
];

/// Every container the form offers.
final List<ContainerSpec> kContainers = <ContainerSpec>[
  ContainerSpec(
    id: 'mp4',
    muxer: 'mp4',
    name: 'MP4',
    extension: 'mp4',
    videoCodecs: <String>{'mpeg4', 'h263', 'mpeg2video', 'mjpeg', 'png'},
    audioCodecs: <String>{'aac', 'ac3', 'eac3', 'mp2', 'alac'},
    options: _movFlags,
  ),
  ContainerSpec(
    id: 'mov',
    muxer: 'mov',
    name: 'QuickTime',
    extension: 'mov',
    videoCodecs: <String>{
      'mpeg4',
      'h263',
      'mpeg2video',
      'mjpeg',
      'prores',
      'dnxhd',
      'png',
      'qtrle',
      'rawvideo',
      'dvvideo',
    },
    audioCodecs: <String>{
      'aac',
      'ac3',
      'eac3',
      'mp2',
      'alac',
      'pcm_s16le',
      'pcm_s24le',
      'pcm_f32le',
    },
    options: _movFlags,
  ),
  ContainerSpec(
    id: 'matroska',
    muxer: 'matroska',
    name: 'Matroska',
    extension: 'mkv',
    videoCodecs: <String>{
      'mpeg4',
      'mpeg2video',
      'mpeg1video',
      'h263',
      'mjpeg',
      'ljpeg',
      'png',
      'gif',
      'ffv1',
      'huffyuv',
      'utvideo',
      'dnxhd',
      'dvvideo',
      'rawvideo',
      'flv',
      'wmv2',
      'qtrle',
      'zmbv',
    },
    audioCodecs: <String>{
      'aac',
      'ac3',
      'eac3',
      'mp2',
      'flac',
      'alac',
      'opus',
      'vorbis',
      'pcm_s16le',
      'pcm_s24le',
      'pcm_f32le',
      'truehd',
      'wavpack',
      'tta',
      'wmav2',
    },
    options: <OptionSpec>[
      IntOption(
        flag: '-cluster_time_limit',
        labelKey: I18nKey.optClusterTime,
        min: 0,
        unit: 'ms',
        advanced: true,
      ),
      IntOption(
        flag: '-cluster_size_limit',
        labelKey: I18nKey.optClusterSize,
        min: 0,
        unit: 'B',
        advanced: true,
      ),
    ],
  ),
  ContainerSpec(
    id: 'webm',
    muxer: 'webm',
    name: 'WebM',
    extension: 'webm',
    videoCodecs: <String>{'mjpeg'},
    audioCodecs: <String>{'opus', 'vorbis'},
    options: <OptionSpec>[
      IntOption(
        flag: '-cluster_time_limit',
        labelKey: I18nKey.optClusterTime,
        min: 0,
        unit: 'ms',
        advanced: true,
      ),
    ],
  ),
  ContainerSpec(
    id: 'avi',
    muxer: 'avi',
    name: 'AVI',
    extension: 'avi',
    videoCodecs: <String>{
      'mpeg4',
      'mjpeg',
      'ffv1',
      'huffyuv',
      'rawvideo',
      'wmv2',
      'dvvideo',
    },
    audioCodecs: <String>{'mp2', 'ac3', 'pcm_s16le', 'pcm_s24le', 'wmav2'},
  ),
  ContainerSpec(
    id: 'mpegts',
    muxer: 'mpegts',
    name: 'MPEG-TS',
    extension: 'ts',
    videoCodecs: <String>{'mpeg2video', 'mpeg1video', 'mpeg4', 'h263'},
    audioCodecs: <String>{'mp2', 'ac3', 'eac3', 'aac'},
    options: <OptionSpec>[
      TextOption(
        flag: '-mpegts_flags',
        labelKey: I18nKey.optMpegtsFlags,
        advanced: true,
      ),
    ],
  ),
  ContainerSpec(
    id: 'flv',
    muxer: 'flv',
    name: 'FLV',
    extension: 'flv',
    videoCodecs: <String>{'flv', 'h263'},
    audioCodecs: <String>{'aac', 'mp2'},
    options: <OptionSpec>[
      TextOption(
        flag: '-flvflags',
        labelKey: I18nKey.optFlvFlags,
        advanced: true,
      ),
    ],
  ),
  ContainerSpec(
    id: 'gif',
    muxer: 'gif',
    name: 'GIF',
    extension: 'gif',
    videoCodecs: <String>{'gif'},
    audioCodecs: <String>{},
    options: <OptionSpec>[
      IntOption(
        flag: '-loop',
        labelKey: I18nKey.optGifLoop,
        min: 0,
        max: 65535,
      ),
    ],
  ),
  ContainerSpec(
    id: 'image2',
    muxer: 'image2',
    name: 'Image sequence',
    extension: 'png',
    videoCodecs: <String>{'png', 'mjpeg', 'ljpeg', 'rawvideo'},
    audioCodecs: <String>{},
  ),
  ContainerSpec(
    id: 'matroska_audio',
    muxer: 'matroska',
    name: 'MKA',
    extension: 'mka',
    videoCodecs: <String>{},
    audioCodecs: <String>{
      'flac',
      'alac',
      'opus',
      'vorbis',
      'pcm_s16le',
      'pcm_s24le',
      'truehd',
      'wavpack',
      'tta',
    },
    audioOnly: true,
  ),
  ContainerSpec(
    id: 'flac',
    muxer: 'flac',
    name: 'FLAC',
    extension: 'flac',
    videoCodecs: <String>{},
    audioCodecs: <String>{'flac'},
    audioOnly: true,
  ),
  ContainerSpec(
    id: 'wav',
    muxer: 'wav',
    name: 'WAV',
    extension: 'wav',
    videoCodecs: <String>{},
    audioCodecs: <String>{'pcm_s16le', 'pcm_s24le', 'pcm_f32le'},
    audioOnly: true,
  ),
  ContainerSpec(
    id: 'ogg',
    muxer: 'ogg',
    name: 'Ogg',
    extension: 'ogg',
    videoCodecs: <String>{},
    audioCodecs: <String>{'vorbis', 'opus', 'flac'},
    audioOnly: true,
    options: <OptionSpec>[
      IntOption(
        flag: '-page_duration',
        labelKey: I18nKey.optPageDuration,
        min: 0,
        unit: 'us',
        advanced: true,
      ),
    ],
  ),
  ContainerSpec(
    id: 'opus',
    muxer: 'opus',
    name: 'Ogg Opus',
    extension: 'opus',
    videoCodecs: <String>{},
    audioCodecs: <String>{'opus'},
    audioOnly: true,
  ),
  ContainerSpec(
    id: 'm4a',
    muxer: 'ipod',
    name: 'M4A',
    extension: 'm4a',
    videoCodecs: <String>{},
    audioCodecs: <String>{'aac', 'alac'},
    audioOnly: true,
    options: _movFlags,
  ),
  ContainerSpec(
    id: 'ac3',
    muxer: 'ac3',
    name: 'AC-3',
    extension: 'ac3',
    videoCodecs: <String>{},
    audioCodecs: <String>{'ac3'},
    audioOnly: true,
  ),
  ContainerSpec(
    id: 'adts',
    muxer: 'adts',
    name: 'ADTS AAC',
    extension: 'aac',
    videoCodecs: <String>{},
    audioCodecs: <String>{'aac'},
    audioOnly: true,
  ),
  ContainerSpec(
    id: 'wv',
    muxer: 'wv',
    name: 'WavPack container',
    extension: 'wv',
    videoCodecs: <String>{},
    audioCodecs: <String>{'wavpack'},
    audioOnly: true,
  ),
];
