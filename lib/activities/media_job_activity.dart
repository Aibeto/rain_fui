/// The single-file encode form.
///
/// Opened from the add-source flow when exactly one file was picked. Everything
/// on this page is derived from the static capability table: the codecs offered
/// for the detected media kind, the containers those codecs can be muxed into,
/// and the options the selected encoder and muxer actually expose.
library;

import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../services/job_queue.dart';
import '../services/output_directory.dart';
import '../src/media/capabilities.dart';
import '../src/media/capabilities_data.dart';
import '../src/media/codec_spec.dart';
import '../src/media/container_spec.dart';
import '../src/media/encode_request.dart';
import '../src/media/media_kind.dart';
import '../src/media/option_spec.dart';
import '../theme/app_theme.dart';
import '../theme/metrics.dart';
import '../widgets/mini_icon_button.dart';

/// Encode settings for one picked file.
class MediaJobActivity extends StatefulWidget {
  /// Creates the form for [file].
  const MediaJobActivity({super.key, required this.file});

  /// The file the user picked.
  final SelectedFile file;

  /// Route used by the add-source flow.
  static Route<void> route(SelectedFile file) => FluentPageRoute<void>(
    builder: (BuildContext context) => MediaJobActivity(file: file),
  );

  @override
  State<MediaJobActivity> createState() => _MediaJobActivityState();
}

class _MediaJobActivityState extends State<MediaJobActivity> {
  late final MediaKind _kind;
  late final TextEditingController _outputName;
  final TextEditingController _customArgs = TextEditingController();
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};

  CodecSpec? _video;
  CodecSpec? _audio;
  ContainerSpec? _container;
  String? _outputDir;
  String? _videoDecoder;
  String? _audioDecoder;
  final Map<String, String> _values = <String, String>{};
  bool _advancedOpen = false;

  /// How the chosen video encoder is told what to aim for. `-q:v` and `-b:v`
  /// answer the same question, so the form asks for the mode first and only
  /// shows the parameters that mode actually uses.
  _RateMode _videoRateMode = _RateMode.auto;

  @override
  void initState() {
    super.initState();
    _kind = detectMediaKind(widget.file.name);
    _outputDir = OutputDirectory.defaultPath;
    _outputName = TextEditingController(
      text: _defaultBaseName(widget.file.name),
    );
    _resetToDefaults();
  }

  @override
  void dispose() {
    _outputName.dispose();
    _customArgs.dispose();
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _defaultBaseName(String fileName) {
    final String ext = p.extension(fileName);
    return ext.isEmpty
        ? fileName
        : fileName.substring(0, fileName.length - ext.length);
  }

  /// Picks the first container that can hold the default codecs for [_kind].
  void _resetToDefaults() {
    final bool wantsVideo = _kind != MediaKind.audio;
    final bool wantsAudio = _kind != MediaKind.image;
    _video = wantsVideo ? _preferredVideoCodec() : null;
    _audio = wantsAudio ? _preferredAudioCodec() : null;
    _container = _firstContainer(_video?.id, _audio?.id);
    final ContainerSpec? container = _container;
    if (container != null) {
      if (_video != null && !container.acceptsVideo(_video!.id)) {
        _video = MediaCapabilities.videoCodecsFor(container).isEmpty
            ? null
            : MediaCapabilities.videoCodecsFor(container).first;
      }
      if (_audio != null && !container.acceptsAudio(_audio!.id)) {
        _audio = MediaCapabilities.audioCodecsFor(container).isEmpty
            ? null
            : MediaCapabilities.audioCodecsFor(container).first;
      }
    }
    _values.clear();
  }

  CodecSpec? _preferredVideoCodec() {
    // A still image has to start on an image encoder; mpeg4 as the first entry
    // of the full list would send a PNG through an MP4 muxer.
    if (_kind == MediaKind.image) {
      for (final String id in const <String>[
        'png',
        'mjpeg',
        'ljpeg',
        'gif',
        'zmbv',
      ]) {
        final CodecSpec? codec = MediaCapabilities.videoCodec(id);
        if (codec != null) {
          return codec;
        }
      }
    }
    final List<CodecSpec> codecs = MediaCapabilities.videoCodecs;
    return codecs.isEmpty ? null : codecs.first;
  }

  CodecSpec? _preferredAudioCodec() {
    final List<CodecSpec> codecs = MediaCapabilities.audioCodecs;
    return codecs.isEmpty ? null : codecs.first;
  }

  ContainerSpec? _firstContainer(String? videoId, String? audioId) {
    final List<ContainerSpec> candidates = MediaCapabilities.containersFor(
      kind: _kind,
      videoCodecId: videoId,
      audioCodecId: audioId,
    );
    if (candidates.isNotEmpty) {
      return candidates.first;
    }
    final List<ContainerSpec> audioOnly = MediaCapabilities.containersFor(
      kind: MediaKind.audio,
    );
    return audioOnly.isEmpty ? null : audioOnly.first;
  }

  /// Flags that choose between quality and bitrate; which of them are shown
  /// depends on [_videoRateMode].
  static const Set<String> _videoRateFlags = <String>{
    '-q:v',
    '-b:v',
    '-maxrate',
    '-bufsize',
  };

  bool get _videoHasQuality =>
      _video?.options.any((OptionSpec spec) => spec.flag == '-q:v') ?? false;

  bool get _videoHasBitrate =>
      _video?.options.any((OptionSpec spec) => spec.flag == '-b:v') ?? false;

  bool get _showsRateMode => _videoHasQuality || _videoHasBitrate;

  Set<String> get _visibleRateFlags => switch (_videoRateMode) {
    _RateMode.auto => const <String>{},
    _RateMode.quality => const <String>{'-q:v'},
    _RateMode.bitrate => const <String>{'-b:v'},
    _RateMode.cbr => const <String>{'-b:v', '-maxrate', '-bufsize'},
  };

  /// Target bitrate has no sensible default, so the form refuses to start
  /// until one is typed when the mode needs it.
  bool get _rateReady {
    if (_videoRateMode != _RateMode.bitrate &&
        _videoRateMode != _RateMode.cbr) {
      return true;
    }
    return (_values['-b:v'] ?? '').trim().isNotEmpty;
  }

  List<OptionSpec> _withRateMode(List<OptionSpec> specs) {
    if (!_showsRateMode) {
      return specs;
    }
    return specs
        .where(
          (OptionSpec spec) =>
              !_videoRateFlags.contains(spec.flag) ||
              _visibleRateFlags.contains(spec.flag),
        )
        .toList();
  }

  List<OptionSpec> get _basicOptions => _withRateMode(<OptionSpec>[
    if (_video != null) ..._video!.basicOptions,
    if (_audio != null) ..._audio!.basicOptions,
    if (_container != null) ..._container!.basicOptions,
  ]);

  List<OptionSpec> get _advancedOptions => _withRateMode(<OptionSpec>[
    if (_video != null) ..._video!.advancedOptions,
    if (_audio != null) ..._audio!.advancedOptions,
    if (_container != null) ..._container!.advancedOptions,
  ]);

  TextEditingController _controllerFor(OptionSpec spec) {
    return _fields.putIfAbsent(
      spec.flag,
      () => TextEditingController(
        text: _values[spec.flag] ?? spec.initialValue ?? '',
      ),
    );
  }

  void _setVideo(CodecSpec? codec) {
    setState(() {
      _video = codec;
      _videoRateMode = _RateMode.auto;
      _values.removeWhere((String flag, _) => _isVideoFlag(flag));
      // The new encoder may not fit the current container; move to the first
      // container that can hold it instead of leaving an impossible pair.
      if (_container != null &&
          codec != null &&
          !_container!.acceptsVideo(codec.id)) {
        final List<ContainerSpec> allowed = MediaCapabilities.containersFor(
          kind: _kind,
          videoCodecId: codec.id,
          audioCodecId: _audio?.id,
        );
        _container = allowed.isEmpty ? null : allowed.first;
      }
    });
  }

  void _setAudio(CodecSpec? codec) {
    setState(() {
      _audio = codec;
      _values.removeWhere((String flag, _) => _isAudioFlag(flag));
      if (_container != null &&
          codec != null &&
          !_container!.acceptsAudio(codec.id)) {
        final List<ContainerSpec> allowed = MediaCapabilities.containersFor(
          kind: _kind,
          videoCodecId: _video?.id,
          audioCodecId: codec.id,
        );
        _container = allowed.isEmpty ? null : allowed.first;
      }
    });
  }

  bool _isVideoFlag(String flag) =>
      _video?.options.any((OptionSpec spec) => spec.flag == flag) ?? false;

  bool _isAudioFlag(String flag) =>
      _audio?.options.any((OptionSpec spec) => spec.flag == flag) ?? false;

  void _setContainer(ContainerSpec? container) {
    setState(() {
      _container = container;
      if (container == null) {
        return;
      }
      if (_video != null && !container.acceptsVideo(_video!.id)) {
        final List<CodecSpec> allowed = MediaCapabilities.videoCodecsFor(
          container,
        );
        _video = allowed.isEmpty ? null : allowed.first;
      }
      if (_audio != null && !container.acceptsAudio(_audio!.id)) {
        final List<CodecSpec> allowed = MediaCapabilities.audioCodecsFor(
          container,
        );
        _audio = allowed.isEmpty ? null : allowed.first;
      }
      _values.clear();
    });
  }

  String _outputFileName() {
    final ContainerSpec? container = _container;
    final String typed = _outputName.text.trim();
    String base = typed.isEmpty ? _defaultBaseName(widget.file.name) : typed;
    if (container == null) {
      return base;
    }
    final String suffix = '.${container.extension}';
    if (base.toLowerCase().endsWith(suffix)) {
      return base;
    }
    // Typing "clip.mkv" while the container is MP4 has to produce "clip.mp4",
    // not "clip.mkv.mp4": a known media extension is replaced, anything else
    // is kept and the container extension is appended.
    final String extension = p.extension(base).toLowerCase();
    if (_mediaExtensions.contains(extension.replaceFirst('.', ''))) {
      base = base.substring(0, base.length - extension.length);
    }
    return '$base$suffix';
  }

  /// Extensions that name a real media file, used to decide whether a typed
  /// name already carries one.
  static const Set<String> _mediaExtensions = <String>{
    'mp4',
    'm4v',
    'mov',
    'mkv',
    'mka',
    'webm',
    'avi',
    'ts',
    'm2ts',
    'flv',
    'gif',
    'png',
    'apng',
    'jpg',
    'jpeg',
    'bmp',
    'tiff',
    'wav',
    'flac',
    'ogg',
    'opus',
    'm4a',
    'ac3',
    'adts',
    'aac',
    'wv',
    'nut',
    'asf',
    'wmv',
    'dv',
    'mxf',
    'yuv',
    'y4m',
    'smjpeg',
    'swf',
  };

  String? _outputPath() {
    final String? directory = _outputDir;
    if (directory != null) {
      return p.join(directory, _outputFileName());
    }
    final String? input = widget.file.path;
    if (input == null || input.isEmpty) {
      return null;
    }
    // No Downloads folder on this platform: keep the result next to the source.
    return p.join(p.dirname(input), _outputFileName());
  }

  EncodeRequest _buildRequest() {
    final String? output = _outputPath();
    return EncodeRequest(
      kind: _kind,
      inputPath: widget.file.path,
      inputName: widget.file.name,
      outputPath: output ?? _outputFileName(),
      container: _container!,
      videoCodec: _video,
      audioCodec: _audio,
      videoDecoder: _kind == MediaKind.audio ? null : _videoDecoder,
      audioDecoder: _kind == MediaKind.image ? null : _audioDecoder,
      optionValues: Map<String, String>.of(_values),
      customArgs: _customArgs.text,
    );
  }

  Future<void> _cancel() async {
    final bool discard = await _confirmDiscard() ?? false;
    if (!discard || !mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<bool?> _confirmDiscard() {
    final AppL10n l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => ContentDialog(
        title: Text(l10n(I18nKey.jobDiscardTitle)),
        content: Text(l10n(I18nKey.jobDiscardBody)),
        actions: <Widget>[
          Button(
            child: Text(l10n(I18nKey.jobDiscardKeep)),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: Text(l10n(I18nKey.jobDiscardConfirm)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final ContainerSpec? container = _container;
    if (container == null) {
      return;
    }
    if (_kind == MediaKind.video && _video == null) {
      return;
    }
    final String? directory = await OutputDirectory.ensure();
    if (!mounted) {
      return;
    }
    if (directory != null && directory != _outputDir) {
      setState(() => _outputDir = directory);
    }
    JobQueue.instance.enqueue(_buildRequest());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    final List<OptionSpec> advanced = _advancedOptions;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              title: l10n(I18nKey.jobPageTitle),
              subtitle: widget.file.name,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppMetrics.gutter,
                  8,
                  AppMetrics.gutter,
                  24,
                ),
                // A wide window would otherwise stretch every field across the
                // screen; the form keeps a readable measure and stays centred.
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppMetrics.contentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _FileCard(file: widget.file, kind: _kind),
                        const SizedBox(height: AppMetrics.sectionGap),
                        _sectionTitle(context, I18nKey.jobSectionCodecs),
                        const SizedBox(height: AppMetrics.sectionTitleGap),
                        _CodecSelectors(
                          kind: _kind,
                          video: _video,
                          audio: _audio,
                          container: _container,
                          onVideo: _setVideo,
                          onAudio: _setAudio,
                          onContainer: _setContainer,
                        ),
                        const SizedBox(height: 10),
                        _OutputField(
                          controller: _outputName,
                          suffix: _container == null
                              ? ''
                              : '.${_container!.extension}',
                          directory: _outputPath() == null
                              ? null
                              : p.dirname(_outputPath()!),
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: AppMetrics.sectionGap),
                        _sectionTitle(context, I18nKey.jobSectionInput),
                        const SizedBox(height: AppMetrics.sectionTitleGap),
                        _DecoderRows(
                          kind: _kind,
                          videoDecoder: _videoDecoder,
                          audioDecoder: _audioDecoder,
                          onVideo: (String? value) =>
                              setState(() => _videoDecoder = value),
                          onAudio: (String? value) =>
                              setState(() => _audioDecoder = value),
                        ),
                        const SizedBox(height: AppMetrics.sectionGap),
                        _sectionTitle(context, I18nKey.jobSectionBasic),
                        const SizedBox(height: AppMetrics.sectionTitleGap),
                        if (_showsRateMode) ...<Widget>[
                          _RateModeRow(
                            mode: _videoRateMode,
                            hasQuality: _videoHasQuality,
                            hasBitrate: _videoHasBitrate,
                            onChanged: _setVideoRateMode,
                          ),
                          if (!_rateReady) ...<Widget>[
                            Text(
                              l10n(I18nKey.jobRateRequired),
                              style: theme.typography.caption?.copyWith(
                                color: theme.accentColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          const SizedBox(height: 6),
                        ],
                        _OptionGrid(
                          specs: _basicOptions,
                          valueOf: _values,
                          controllerFor: _controllerFor,
                          onChanged: _onOptionChanged,
                        ),
                        const SizedBox(height: AppMetrics.rowGap + 6),
                        _AdvancedExpander(
                          open: _advancedOpen,
                          count: advanced.length,
                          onToggle: () =>
                              setState(() => _advancedOpen = !_advancedOpen),
                          child: _OptionGrid(
                            specs: advanced,
                            valueOf: _values,
                            controllerFor: _controllerFor,
                            onChanged: _onOptionChanged,
                          ),
                        ),
                        const SizedBox(height: AppMetrics.sectionGap),
                        _sectionTitle(context, I18nKey.jobSectionCustom),
                        const SizedBox(height: AppMetrics.sectionTitleGap),
                        TextBox(
                          controller: _customArgs,
                          placeholder: l10n(I18nKey.jobCustomHint),
                          style: AppTheme.mono(
                            theme.typography.body,
                            l10n.locale,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _ActionBar(
              onCancel: _cancel,
              onStart: _start,
              canStart:
                  _container != null &&
                  _rateReady &&
                  (_kind != MediaKind.video || _video != null) &&
                  (_kind != MediaKind.audio || _audio != null),
            ),
          ],
        ),
      ),
    );
  }

  void _setVideoRateMode(_RateMode mode) {
    setState(() {
      _videoRateMode = mode;
      for (final String flag in _videoRateFlags) {
        if (_visibleRateFlags.contains(flag)) {
          continue;
        }
        _values.remove(flag);
        _fields.remove(flag)?.dispose();
      }
      // Constant quality needs a number to send; 2 is what FFmpeg's own
      // MPEG-family encoders pick when nothing is specified.
      if (mode == _RateMode.quality && (_values['-q:v'] ?? '').isEmpty) {
        _values['-q:v'] = '2';
        _fields['-q:v']?.text = '2';
      }
    });
  }

  void _onOptionChanged(OptionSpec spec, String? value) {
    final bool clearing = value == null || value.isEmpty;
    setState(() {
      if (!clearing && spec.exclusiveGroup != null) {
        // Constant quality and target bitrate are two answers to one question,
        // so picking one has to take the others off the command line.
        for (final OptionSpec sibling in <OptionSpec>[
          ..._basicOptions,
          ..._advancedOptions,
        ]) {
          if (identical(sibling, spec) ||
              sibling.exclusiveGroup != spec.exclusiveGroup) {
            continue;
          }
          if (_values.remove(sibling.flag) != null) {
            _fields[sibling.flag]?.clear();
          }
        }
      }
      if (clearing) {
        _values.remove(spec.flag);
      } else {
        _values[spec.flag] = value;
      }
    });
  }

  Widget _sectionTitle(BuildContext context, String key) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Text(
      context.l10n(key),
      style: theme.typography.bodyStrong?.copyWith(
        color: theme.resources.textFillColorSecondary,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    return Container(
      height: 56,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppMetrics.gutter,
        0,
        AppMetrics.gutter,
        0,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
          MiniIconButton(
            icon: FluentIcons.arrow_left_24_regular,
            tooltip: context.l10n(I18nKey.actionClose),
            onPressed: onBack,
            size: 28,
            iconSize: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.typography.subtitle),
                Text(
                  subtitle,
                  style: theme.typography.caption?.copyWith(
                    color: resources.textFillColorSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.kind});

  final SelectedFile file;
  final MediaKind kind;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    return Container(
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: resources.cardStrokeColorDefault),
      ),
      child: Row(
        // The icon is a single line; centring it against the name and the file
        // name underneath keeps it from floating above the first line.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            switch (kind) {
              MediaKind.audio => FluentIcons.music_note_2_24_regular,
              MediaKind.image => FluentIcons.image_24_regular,
              _ => FluentIcons.video_24_regular,
            },
            size: 20,
            color: resources.textFillColorSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n(_kindKey(kind)), style: theme.typography.bodyStrong),
                const SizedBox(height: 2),
                SelectableText(
                  file.name,
                  style: AppTheme.mono(
                    theme.typography.caption?.copyWith(
                      color: resources.textFillColorSecondary,
                    ),
                    l10n.locale,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _kindKey(MediaKind kind) => switch (kind) {
    MediaKind.video => I18nKey.mediaTypeVideo,
    MediaKind.audio => I18nKey.mediaTypeAudio,
    MediaKind.image => I18nKey.mediaTypeImage,
    MediaKind.unknown => I18nKey.mediaTypeUnknown,
  };
}

class _CodecSelectors extends StatelessWidget {
  const _CodecSelectors({
    required this.kind,
    required this.video,
    required this.audio,
    required this.container,
    required this.onVideo,
    required this.onAudio,
    required this.onContainer,
  });

  final MediaKind kind;
  final CodecSpec? video;
  final CodecSpec? audio;
  final ContainerSpec? container;
  final ValueChanged<CodecSpec?> onVideo;
  final ValueChanged<CodecSpec?> onAudio;
  final ValueChanged<ContainerSpec?> onContainer;

  @override
  Widget build(BuildContext context) {
    final AppL10n l10n = context.l10n;
    final List<CodecSpec> videos = container == null
        ? MediaCapabilities.videoCodecs
        : MediaCapabilities.videoCodecsFor(container!);
    final List<CodecSpec> audios = container == null
        ? MediaCapabilities.audioCodecs
        : MediaCapabilities.audioCodecsFor(container!);

    // Only the containers that can hold what is currently selected, plus the
    // current one so a stale choice never disappears out from under the field.
    final ContainerSpec? current = container;
    final List<ContainerSpec> containers = MediaCapabilities.containersFor(
      kind: kind,
      videoCodecId: video?.id,
      audioCodecId: audio?.id,
    );
    if (current != null && !containers.contains(current)) {
      containers.insert(0, current);
    }

    // One width for the three pickers: measuring each row on its own left the
    // fields starting at three different x.
    final double width = _comboWidth(context, <String>[
      if (kind != MediaKind.video) l10n(I18nKey.jobNoVideo),
      if (kind != MediaKind.audio) ...videos.map((CodecSpec c) => c.name),
      if (kind != MediaKind.image) l10n(I18nKey.jobNoAudio),
      if (kind != MediaKind.image) ...audios.map((CodecSpec c) => c.name),
      l10n(I18nKey.jobNoContainer),
      ...containers.map((ContainerSpec c) => '${c.name} (.${c.extension})'),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (kind != MediaKind.audio)
          _PickerRow<CodecSpec>(
            label: l10n(I18nKey.jobLabelVideoCodec),
            items: videos,
            value: video,
            labelOf: (CodecSpec c) => c.name,
            onChanged: onVideo,
            allowNone: kind != MediaKind.video,
            noneLabel: l10n(I18nKey.jobNoVideo),
            width: width,
          ),
        if (kind != MediaKind.image)
          _PickerRow<CodecSpec>(
            label: l10n(I18nKey.jobLabelAudioCodec),
            items: audios,
            value: audio,
            labelOf: (CodecSpec c) => c.name,
            onChanged: onAudio,
            allowNone: true,
            noneLabel: l10n(I18nKey.jobNoAudio),
            width: width,
          ),
        _PickerRow<ContainerSpec>(
          label: l10n(I18nKey.jobLabelContainer),
          items: containers,
          value: current,
          labelOf: (ContainerSpec c) => '${c.name} (.${c.extension})',
          onChanged: onContainer,
          allowNone: false,
          noneLabel: l10n(I18nKey.jobNoContainer),
          width: width,
        ),
      ],
    );
  }
}

/// Width a dropdown needs so its widest entry fits without being cut.
///
/// Fluent sizes a popup from its longest item but leaves the closed field at
/// whatever width the parent gives it, so the two drift apart. Measuring the
/// same strings here keeps the field, the popup and the row edge consistent.
double _comboWidth(
  BuildContext context,
  Iterable<String> labels, {
  double min = 120,
  double max = 280,
  TextStyle? style,
}) {
  final TextStyle textStyle = style ?? FluentTheme.of(context).typography.body!;
  final TextScaler scaler = MediaQuery.textScalerOf(context);
  final TextDirection direction = Directionality.of(context);
  double widest = 0;
  for (final String label in labels) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    widest = math.max(widest, painter.width);
  }
  // Chevron, horizontal padding and a little slack for the caret.
  return (widest + 45).clamp(min, max);
}

/// How the encoder is asked to pick a quality.
///
/// FFmpeg treats constant quality (`-q:v`) and target bitrate (`-b:v`) as
/// alternatives, and capped VBR (`-maxrate` + `-bufsize`) only makes sense on
/// top of a bitrate. Making the choice explicit keeps the two from reaching the
/// command line together.
enum _RateMode {
  auto(I18nKey.jobRateAuto),
  quality(I18nKey.jobRateQuality),
  bitrate(I18nKey.jobRateBitrate),
  cbr(I18nKey.jobRateCbr);

  const _RateMode(this.labelKey);

  final String labelKey;
}

/// Dropdown that picks the rate-control mode.
class _RateModeRow extends StatelessWidget {
  const _RateModeRow({
    required this.mode,
    required this.hasQuality,
    required this.hasBitrate,
    required this.onChanged,
  });

  final _RateMode mode;
  final bool hasQuality;
  final bool hasBitrate;
  final ValueChanged<_RateMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    final List<_RateMode> modes = <_RateMode>[
      _RateMode.auto,
      if (hasQuality) _RateMode.quality,
      if (hasBitrate) _RateMode.bitrate,
      if (hasBitrate) _RateMode.cbr,
    ];
    final double width = _comboWidth(
      context,
      modes.map((_RateMode m) => l10n(m.labelKey)),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n(I18nKey.jobRateMode),
              style: theme.typography.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: width,
            child: ComboBox<_RateMode>(
              isExpanded: true,
              popupColor: theme.menuColor,
              popupConstraints: BoxConstraints(
                minWidth: width,
                maxWidth: width,
                maxHeight: 280,
              ),
              value: mode,
              items: <ComboBoxItem<_RateMode>>[
                for (final _RateMode option in modes)
                  ComboBoxItem<_RateMode>(
                    value: option,
                    child: Text(
                      l10n(option.labelKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (_RateMode? value) {
                if (value != null) {
                  onChanged(value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.items,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    required this.allowNone,
    required this.noneLabel,
    this.width,
  });

  final String label;
  final List<T> items;
  final T? value;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final bool allowNone;
  final String noneLabel;

  /// Width to use instead of measuring this row on its own; the codec rows
  /// pass one shared width so the three dropdowns start at the same x.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final double width =
        this.width ??
        _comboWidth(context, <String>[
          if (allowNone) noneLabel,
          for (final T item in items) labelOf(item),
        ]);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.typography.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: width,
            child: ComboBox<T?>(
              isExpanded: true,
              popupConstraints: BoxConstraints(
                minWidth: width,
                maxWidth: width,
                maxHeight: 360,
              ),
              popupColor: FluentTheme.of(context).menuColor,
              placeholder: Text(noneLabel),
              value: value,
              items: <ComboBoxItem<T?>>[
                if (allowNone)
                  ComboBoxItem<T?>(value: null, child: Text(noneLabel)),
                for (final T item in items)
                  ComboBoxItem<T?>(
                    value: item,
                    child: Text(
                      labelOf(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (T? selected) {
                if (selected == null && !allowNone) {
                  return;
                }
                onChanged(selected);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional input decoders; leaving them on auto is the normal case.
class _DecoderRows extends StatelessWidget {
  const _DecoderRows({
    required this.kind,
    required this.videoDecoder,
    required this.audioDecoder,
    required this.onVideo,
    required this.onAudio,
  });

  final MediaKind kind;
  final String? videoDecoder;
  final String? audioDecoder;
  final ValueChanged<String?> onVideo;
  final ValueChanged<String?> onAudio;

  @override
  Widget build(BuildContext context) {
    final bool wantsVideo = kind != MediaKind.audio;
    final bool wantsAudio = kind != MediaKind.image;
    final AppL10n l10n = context.l10n;
    // Both decoder rows share one width, sized by the wider of the two lists.
    final double width = _comboWidth(context, <String>[
      l10n(I18nKey.jobDecoderAuto),
      if (wantsVideo) ...kVideoDecoders,
      if (wantsAudio) ...kAudioDecoders,
    ], max: 200);
    return Column(
      children: <Widget>[
        if (wantsVideo)
          _DecoderRow(
            labelKey: I18nKey.jobLabelVideoDecoder,
            value: videoDecoder,
            options: kVideoDecoders,
            onChanged: onVideo,
            width: width,
          ),
        if (wantsVideo && wantsAudio) const SizedBox(height: 8),
        if (wantsAudio)
          _DecoderRow(
            labelKey: I18nKey.jobLabelAudioDecoder,
            value: audioDecoder,
            options: kAudioDecoders,
            onChanged: onAudio,
            width: width,
          ),
      ],
    );
  }
}

class _DecoderRow extends StatelessWidget {
  const _DecoderRow({
    required this.labelKey,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.width,
  });

  final String labelKey;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    return Row(
      children: <Widget>[
        Expanded(child: Text(l10n(labelKey), style: theme.typography.body)),
        const SizedBox(width: 12),
        SizedBox(
          width: width,
          child: ComboBox<String?>(
            isExpanded: true,
            popupColor: theme.menuColor,
            popupConstraints: BoxConstraints(
              minWidth: width,
              maxWidth: width,
              maxHeight: 320,
            ),
            value: value,
            placeholder: Text(l10n(I18nKey.jobDecoderAuto)),
            items: <ComboBoxItem<String?>>[
              ComboBoxItem<String?>(
                value: null,
                child: Text(l10n(I18nKey.jobDecoderAuto)),
              ),
              for (final String name in options)
                ComboBoxItem<String?>(
                  value: name,
                  child: Text(
                    name,
                    style: AppTheme.mono(theme.typography.caption, l10n.locale),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _OutputField extends StatelessWidget {
  const _OutputField({
    required this.controller,
    required this.suffix,
    required this.directory,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String suffix;

  /// Folder the finished file is written to, shown under the name field.
  final String? directory;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    final Widget field = Row(
      children: <Widget>[
        SizedBox(
          width: AppMetrics.fieldWidth,
          child: Text(
            l10n(I18nKey.jobLabelOutputName),
            style: theme.typography.body,
          ),
        ),
        Expanded(
          child: TextBox(
            controller: controller,
            onChanged: (_) => onChanged(),
            style: AppTheme.mono(theme.typography.body, l10n.locale),
            // The extension lives inside the box, so the field ends where the
            // dropdowns above it end instead of stopping short of them.
            suffix: suffix.isEmpty
                ? null
                : Text(
                    suffix,
                    style: AppTheme.mono(
                      theme.typography.body?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                      l10n.locale,
                    ),
                  ),
          ),
        ),
      ],
    );
    final String? folder = directory;
    if (folder == null) {
      return field;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        field,
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppMetrics.fieldWidth,
            top: 6,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                FluentIcons.folder_24_regular,
                size: 12,
                color: theme.resources.textFillColorTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder,
                  style: AppTheme.mono(
                    theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                    l10n.locale,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.specs,
    required this.valueOf,
    required this.controllerFor,
    required this.onChanged,
  });

  final List<OptionSpec> specs;
  final Map<String, String> valueOf;
  final TextEditingController Function(OptionSpec) controllerFor;
  final void Function(OptionSpec, String?) onChanged;

  @override
  Widget build(BuildContext context) {
    if (specs.isEmpty) {
      return Text(
        context.l10n(I18nKey.jobNoOptions),
        style: FluentTheme.of(context).typography.caption,
      );
    }
    // Ranged numbers draw their own header plus a full-width slider, so they
    // are stacked below the compact grid instead of sharing a 300 px cell.
    final List<OptionSpec> ranged = specs.where(_isRanged).toList();
    final List<OptionSpec> compact = specs
        .where((OptionSpec s) => !_isRanged(s))
        .toList();
    return _FieldHost(
      valueOf: valueOf,
      onChanged: onChanged,
      controllerFor: controllerFor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (compact.isNotEmpty)
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Share the width evenly instead of wrapping fixed 300 px
                // cells, so the input at the end of a cell lines up with the
                // input of the cell below it.
                final int columns = math.max(
                  1,
                  ((constraints.maxWidth + AppMetrics.columnGap) /
                          (AppMetrics.minCellWidth + AppMetrics.columnGap))
                      .floor(),
                );
                final double cellWidth =
                    (constraints.maxWidth -
                        AppMetrics.columnGap * (columns - 1)) /
                    columns;
                final List<Widget> rows = <Widget>[];
                for (int start = 0; start < compact.length; start += columns) {
                  final List<OptionSpec> slice = compact.sublist(
                    start,
                    math.min(start + columns, compact.length),
                  );
                  if (rows.isNotEmpty) {
                    rows.add(const SizedBox(height: 10));
                  }
                  rows.add(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (
                          int index = 0;
                          index < columns;
                          index++
                        ) ...<Widget>[
                          if (index > 0)
                            const SizedBox(width: AppMetrics.columnGap),
                          SizedBox(
                            width: cellWidth,
                            child: index < slice.length
                                ? _OptionField(spec: slice[index])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                );
              },
            ),
          for (final OptionSpec spec in ranged)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 10),
              child: _OptionField(spec: spec),
            ),
        ],
      ),
    );
  }

  static bool _isRanged(OptionSpec spec) => switch (spec) {
    IntOption(min: != null, max: != null) => true,
    DecimalOption(min: != null, max: != null) => true,
    _ => false,
  };
}

class _OptionField extends StatelessWidget {
  const _OptionField({required this.spec});

  final OptionSpec spec;

  @override
  Widget build(BuildContext context) {
    // Ranged numbers get the wide layout: header line plus a full-width
    // slider, so the range is readable instead of squeezed into 132 px.
    switch (spec) {
      case final IntOption number when number.min != null && number.max != null:
        return _RangeField(
          spec: number,
          min: number.min!.toDouble(),
          max: number.max!.toDouble(),
          integral: true,
        );
      case final DecimalOption number
          when number.min != null && number.max != null:
        return _RangeField(
          spec: number,
          min: number.min!,
          max: number.max!,
          integral: false,
        );
      case final OptionSpec _:
        break;
    }

    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                spec.labelKey == null ? spec.flag : l10n(spec.labelKey!),
                style: theme.typography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                spec.labelKey == null ? '' : spec.flag,
                style: AppTheme.mono(
                  theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorTertiary,
                  ),
                  l10n.locale,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: _trailingWidth(context), child: _editor(context)),
      ],
    );
  }

  /// Width of the trailing control: dropdowns take the width of their widest
  /// entry, everything else keeps the compact column width.
  double _trailingWidth(BuildContext context) {
    final OptionSpec option = spec;
    if (option is! ChoiceOption) {
      return AppMetrics.fieldWidth;
    }
    return _comboWidth(context, <String>[
      if (option.allowEmpty) context.l10n(I18nKey.optionUnset),
      for (final OptionChoice choice in option.choices)
        choice.labelKey == null ? choice.value : context.l10n(choice.labelKey!),
    ]);
  }

  Widget _editor(BuildContext context) {
    final _FieldHost host = _FieldHost.of(context);
    switch (spec) {
      case final ToggleOption toggle:
        final bool on =
            (host.valueOf[toggle.flag] ?? toggle.initialValue) == '1';
        return Checkbox(
          checked: on,
          onChanged: (bool? value) =>
              host.onChanged(toggle, (value ?? false) ? '1' : '0'),
        );
      case final ChoiceOption choice:
        final String? current =
            host.valueOf[choice.flag] ?? choice.initialValue;
        final double width = _trailingWidth(context);
        return ComboBox<String>(
          isExpanded: true,
          popupColor: FluentTheme.of(context).menuColor,
          popupConstraints: BoxConstraints(
            minWidth: width,
            maxWidth: width,
            maxHeight: 320,
          ),
          value: current,
          placeholder: Text(context.l10n(I18nKey.optionUnset)),
          items: <ComboBoxItem<String>>[
            if (choice.allowEmpty)
              ComboBoxItem<String>(
                value: null,
                child: Text(context.l10n(I18nKey.optionUnset)),
              ),
            for (final OptionChoice option in choice.choices)
              ComboBoxItem<String>(
                value: option.value,
                child: Text(
                  option.labelKey == null
                      ? option.value
                      : context.l10n(option.labelKey!),
                ),
              ),
          ],
          onChanged: (String? value) => host.onChanged(choice, value),
        );
      case final OptionSpec other:
        return TextBox(
          controller: host.controllerFor(other),
          onChanged: (String value) => host.onChanged(other, value),
        );
    }
  }
}

/// Numeric option that declares a range.
///
/// Header line holds the name, the flag, the current value and two buttons
/// (manual input, clear). The slider below spans the full width. The value
/// stays unset until the user moves the thumb or types a number.
class _RangeField extends StatefulWidget {
  const _RangeField({
    required this.spec,
    required this.min,
    required this.max,
    required this.integral,
  });

  final OptionSpec spec;
  final double min;
  final double max;
  final bool integral;

  @override
  State<_RangeField> createState() => _RangeFieldState();
}

class _RangeFieldState extends State<_RangeField> {
  bool _editing = false;
  TextEditingController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _format(double value) =>
      widget.integral ? value.round().toString() : value.toStringAsFixed(2);

  void _startEditing(String? current) {
    _controller ??= TextEditingController();
    _controller!.text = current ?? '';
    _controller!.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller!.text.length,
    );
    setState(() => _editing = true);
  }

  void _commit() {
    final _FieldHost host = _FieldHost.of(context);
    final String raw = _controller?.text.trim() ?? '';
    if (raw.isEmpty) {
      host.onChanged(widget.spec, null);
    } else {
      final double? parsed = double.tryParse(raw);
      if (parsed == null) {
        // Keep the box open so the user can fix the number.
        return;
      }
      host.onChanged(
        widget.spec,
        _format(parsed.clamp(widget.min, widget.max)),
      );
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    final _FieldHost host = _FieldHost.of(context);
    final String? current =
        host.valueOf[widget.spec.flag] ?? widget.spec.initialValue;
    // When the flag is off, the thumb still has to sit on the value the
    // encoder would use, otherwise the row reads as "somewhere in the middle".
    final double fallback =
        double.tryParse(widget.spec.defaultValue ?? '')
            ?.clamp(widget.min, widget.max) ??
        widget.min;
    final double shown =
        double.tryParse(current ?? '')?.clamp(widget.min, widget.max) ??
        fallback;
    final TextStyle mono = AppTheme.mono(
      theme.typography.caption?.copyWith(
        color: resources.textFillColorSecondary,
      ),
      l10n.locale,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Readable name first, the raw flag underneath it, and the value
        // controls on the right of the name line.
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.spec.labelKey == null
                    ? widget.spec.flag
                    : l10n(widget.spec.labelKey!),
                style: theme.typography.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            // A fixed minimum keeps the value chips of two rows on the same
            // x even when one reads "default" and the next reads "31".
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: resources.controlFillColorDefault,
                  border: Border.all(
                    color: resources.controlStrokeColorDefault,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(current ?? l10n(I18nKey.optionUnset), style: mono),
              ),
            ),
            const SizedBox(width: 6),
            MiniIconButton(
              icon: FluentIcons.edit_24_regular,
              tooltip: l10n(I18nKey.optionEdit),
              onPressed: _editing ? null : () => _startEditing(current),
            ),
            MiniIconButton(
              icon: FluentIcons.dismiss_24_regular,
              tooltip: l10n(I18nKey.optionUnset),
              onPressed: current == null && !_editing
                  ? null
                  : () {
                      host.onChanged(widget.spec, null);
                      if (_editing) {
                        setState(() => _editing = false);
                      }
                    },
            ),
          ],
        ),
        if (widget.spec.labelKey != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2, bottom: 2),
            child: Text(widget.spec.flag, style: mono, maxLines: 1),
          ),
        if (_editing)
          Row(
            children: <Widget>[
              Expanded(
                child: TextBox(
                  controller: _controller,
                  placeholder:
                      '${_format(widget.min)} - ${_format(widget.max)}',
                  onSubmitted: (String _) => _commit(),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: MiniIconButton(
                  icon: FluentIcons.checkmark_24_regular,
                  tooltip: l10n(I18nKey.optionEdit),
                  onPressed: _commit,
                ),
              ),
            ],
          )
        else
          Slider(
            value: shown,
            min: widget.min,
            max: widget.max,
            divisions: widget.integral
                ? (widget.max - widget.min).round()
                : null,
            label:
                current ??
                (widget.integral
                    ? shown.round().toString()
                    : shown.toStringAsFixed(2)),
            onChanged: (double value) =>
                host.onChanged(widget.spec, _format(value)),
          ),
      ],
    );
  }
}

/// Carries the form callbacks down to the leaf editors without threading six
/// parameters through every widget.
class _FieldHost extends InheritedWidget {
  const _FieldHost({
    required this.valueOf,
    required this.onChanged,
    required this.controllerFor,
    required super.child,
  });

  final Map<String, String> valueOf;
  final void Function(OptionSpec, String?) onChanged;
  final TextEditingController Function(OptionSpec) controllerFor;

  static _FieldHost of(BuildContext context) {
    final _FieldHost? host = context
        .dependOnInheritedWidgetOfExactType<_FieldHost>();
    assert(host != null, 'No _FieldHost above this option field.');
    return host!;
  }

  @override
  bool updateShouldNotify(_FieldHost oldWidget) => true;
}

class _AdvancedExpander extends StatelessWidget {
  const _AdvancedExpander({
    required this.open,
    required this.count,
    required this.onToggle,
    required this.child,
  });

  final bool open;
  final int count;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HoverButton(
          onPressed: onToggle,
          builder: (BuildContext context, Set<WidgetState> states) {
            return Container(
              height: 36,
              padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 8, 0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: resources.dividerStrokeColorDefault,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    open
                        ? FluentIcons.chevron_up_24_regular
                        : FluentIcons.chevron_down_24_regular,
                    size: 12,
                    color: resources.textFillColorSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n(I18nKey.jobSectionAdvanced),
                    style: theme.typography.bodyStrong,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· $count',
                    style: theme.typography.caption?.copyWith(
                      color: resources.textFillColorTertiary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (open)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 10),
            child: child,
          ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onCancel,
    required this.onStart,
    required this.canStart,
  });

  final VoidCallback onCancel;
  final VoidCallback? onStart;

  /// False while the current codec pair has no container to go into.
  final bool canStart;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    return Container(
      height: 56,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppMetrics.gutter,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
          Button(onPressed: onCancel, child: Text(l10n(I18nKey.jobCancel))),
          const Spacer(),
          FilledButton(
            onPressed: canStart ? onStart : null,
            child: Text(l10n(I18nKey.jobStart)),
          ),
        ],
      ),
    );
  }
}
