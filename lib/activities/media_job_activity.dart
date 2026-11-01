/// The single-file encode form.
///
/// Opened from the add-source flow when exactly one file was picked. Everything
/// on this page is derived from the static capability table: the codecs offered
/// for the detected media kind, the containers those codecs can be muxed into,
/// and the options the selected encoder and muxer actually expose.
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../services/job_queue.dart';
import '../src/media/capabilities.dart';
import '../src/media/codec_spec.dart';
import '../src/media/container_spec.dart';
import '../src/media/encode_request.dart';
import '../src/media/media_kind.dart';
import '../src/media/option_spec.dart';
import '../theme/app_theme.dart';

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
  final Map<String, String> _values = <String, String>{};
  bool _advancedOpen = false;

  @override
  void initState() {
    super.initState();
    _kind = detectMediaKind(widget.file.name);
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

  List<OptionSpec> get _basicOptions => <OptionSpec>[
    if (_video != null) ..._video!.basicOptions,
    if (_audio != null) ..._audio!.basicOptions,
    if (_container != null) ..._container!.basicOptions,
  ];

  List<OptionSpec> get _advancedOptions => <OptionSpec>[
    if (_video != null) ..._video!.advancedOptions,
    if (_audio != null) ..._audio!.advancedOptions,
    if (_container != null) ..._container!.advancedOptions,
  ];

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
      _values.removeWhere((String flag, _) => _isVideoFlag(flag));
    });
  }

  void _setAudio(CodecSpec? codec) {
    setState(() {
      _audio = codec;
      _values.removeWhere((String flag, _) => _isAudioFlag(flag));
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
    final String base = _outputName.text.trim().isEmpty
        ? _defaultBaseName(widget.file.name)
        : _outputName.text.trim();
    if (container == null || base.endsWith('.${container.extension}')) {
      return base;
    }
    return '$base.${container.extension}';
  }

  String? _outputPath() {
    final String? input = widget.file.path;
    if (input == null || input.isEmpty) {
      return null;
    }
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

  void _start() {
    final ContainerSpec? container = _container;
    if (container == null) {
      return;
    }
    if (_kind == MediaKind.video && _video == null) {
      return;
    }
    JobQueue.instance.enqueue(_buildRequest());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    final List<OptionSpec> advanced = _advancedOptions;

    return ColoredBox(
      color: resources.solidBackgroundFillColorBase,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              title: l10n(I18nKey.jobPageTitle),
              subtitle: widget.file.name,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _FileCard(file: widget.file, kind: _kind),
                    const SizedBox(height: 16),
                    _sectionTitle(context, I18nKey.jobSectionCodecs),
                    const SizedBox(height: 8),
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
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle(context, I18nKey.jobSectionBasic),
                    const SizedBox(height: 8),
                    _OptionGrid(
                      specs: _basicOptions,
                      valueOf: _values,
                      controllerFor: _controllerFor,
                      onChanged: _onOptionChanged,
                    ),
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 18),
                    _sectionTitle(context, I18nKey.jobSectionCustom),
                    const SizedBox(height: 8),
                    TextBox(
                      controller: _customArgs,
                      placeholder: l10n(I18nKey.jobCustomHint),
                      style: AppTheme.mono(theme.typography.body, l10n.locale),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            _ActionBar(onCancel: _cancel, onStart: _start),
          ],
        ),
      ),
    );
  }

  void _onOptionChanged(OptionSpec spec, String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
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
      style: theme.typography.bodyStrong?.copyWith(fontSize: 14),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    return Container(
      height: 56,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  file.display,
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
          ),
        _PickerRow<ContainerSpec>(
          label: l10n(I18nKey.jobLabelContainer),
          items: MediaCapabilities.containers,
          value: container,
          labelOf: (ContainerSpec c) => '${c.name} (.${c.extension})',
          onChanged: onContainer,
          allowNone: false,
          noneLabel: l10n(I18nKey.jobNoContainer),
        ),
      ],
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
  });

  final String label;
  final List<T> items;
  final T? value;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final bool allowNone;
  final String noneLabel;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.typography.body?.copyWith(fontSize: 13),
            ),
          ),
          Expanded(
            child: ComboBox<T?>(
              isExpanded: true,
              value: value,
              items: <ComboBoxItem<T?>>[
                if (allowNone)
                  ComboBoxItem<T?>(value: null, child: Text(noneLabel)),
                for (final T item in items)
                  ComboBoxItem<T?>(value: item, child: Text(labelOf(item))),
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

class _OutputField extends StatelessWidget {
  const _OutputField({
    required this.controller,
    required this.suffix,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String suffix;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 132,
          child: Text(
            l10n(I18nKey.jobLabelOutputName),
            style: theme.typography.body?.copyWith(fontSize: 13),
          ),
        ),
        Expanded(
          child: TextBox(
            controller: controller,
            onChanged: (_) => onChanged(),
            style: AppTheme.mono(theme.typography.body, l10n.locale),
          ),
        ),
        if (suffix.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6),
            child: Text(
              suffix,
              style: AppTheme.mono(
                theme.typography.body?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
                l10n.locale,
              ),
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
    return _FieldHost(
      valueOf: valueOf,
      onChanged: onChanged,
      controllerFor: controllerFor,
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: <Widget>[
          for (final OptionSpec spec in specs)
            SizedBox(width: 300, child: _OptionField(spec: spec)),
        ],
      ),
    );
  }
}

class _OptionField extends StatelessWidget {
  const _OptionField({required this.spec});

  final OptionSpec spec;

  @override
  Widget build(BuildContext context) {
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
                    fontSize: 11,
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
        SizedBox(width: 132, child: _editor(context)),
      ],
    );
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
        return ComboBox<String>(
          isExpanded: true,
          value: current,
          items: <ComboBoxItem<String>>[
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
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
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
  const _ActionBar({required this.onCancel, required this.onStart});

  final VoidCallback onCancel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    return Container(
      height: 56,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: resources.solidBackgroundFillColorBase,
        border: Border(
          top: BorderSide(color: resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
          Button(onPressed: onCancel, child: Text(l10n(I18nKey.jobCancel))),
          const Spacer(),
          FilledButton(onPressed: onStart, child: Text(l10n(I18nKey.jobStart))),
        ],
      ),
    );
  }
}
