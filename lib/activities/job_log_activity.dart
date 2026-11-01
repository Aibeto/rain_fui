import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../services/job_queue.dart';
import '../theme/app_theme.dart';

/// Terminal output of one encode job.
///
/// The log is a plain text block rather than a list of rows so the whole
/// transcript can be selected and copied. Auto-scroll keeps the viewport on
/// the newest line while the job is still running; turning it off lets the
/// user read earlier lines without being dragged back down.
class JobLogActivity extends StatefulWidget {
  /// Creates the page for [job].
  const JobLogActivity({required this.job, super.key});

  /// The job whose output is shown.
  final EncodeJob job;

  /// Route used by the task list when a row is tapped.
  static Route<void> route(EncodeJob job) =>
      FluentPageRoute<void>(builder: (_) => JobLogActivity(job: job));

  @override
  State<JobLogActivity> createState() => _JobLogActivityState();
}

class _JobLogActivityState extends State<JobLogActivity> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    widget.job.addListener(_onJobChanged);
  }

  @override
  void dispose() {
    widget.job.removeListener(_onJobChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onJobChanged() {
    if (!_autoScroll) {
      return;
    }
    // The new line only exists after this frame, so jump once it is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    final TextStyle mono = AppTheme.mono(
      theme.typography.body?.copyWith(
        color: theme.resources.textFillColorSecondary,
        height: 1.4,
      ),
      l10n.locale,
    );

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: <Widget>[
          _Header(
            title: l10n(I18nKey.jobLogTitle),
            subtitle: widget.job.displayName,
            autoScroll: _autoScroll,
            onAutoScroll: (bool value) => setState(() => _autoScroll = value),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.job,
              builder: (BuildContext context, Widget? _) {
                final List<String> lines = widget.job.logLines;
                if (lines.isEmpty) {
                  return Center(
                    child: Text(
                      l10n(I18nKey.jobLogEmpty),
                      style: theme.typography.caption,
                    ),
                  );
                }
                return Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      12,
                      16,
                      24,
                    ),
                    child: SelectableText(lines.join('\n'), style: mono),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.autoScroll,
    required this.onAutoScroll,
  });

  final String title;
  final String subtitle;
  final bool autoScroll;
  final ValueChanged<bool> onAutoScroll;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    return Container(
      height: 52,
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 16, 0),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: l10n(I18nKey.actionClose),
            child: IconButton(
              icon: const Icon(FluentIcons.arrow_left_24_regular, size: 14),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: 4),
          Text(title, style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: theme.typography.caption?.copyWith(
                color: resources.textFillColorTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          ToggleSwitch(
            checked: autoScroll,
            onChanged: onAutoScroll,
            content: Text(
              l10n(I18nKey.jobLogAutoscroll),
              style: theme.typography.caption,
            ),
          ),
        ],
      ),
    );
  }
}
