/// The home content region: drop hint, empty state and the task list.
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../services/job_queue.dart';
import '../services/platform_support.dart';

/// Main region of the home screen.
///
/// There is no page heading on purpose: the task list (or the empty state) is
/// the first thing under the top bar.
class HomeContent extends StatelessWidget {
  /// Creates the content region.
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 16),
        child: ListenableBuilder(
          listenable: JobQueue.instance,
          builder: (BuildContext context, Widget? child) {
            final List<EncodeJob> jobs = JobQueue.instance.jobs;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n(I18nKey.jobsTitle),
                  style: theme.typography.bodyStrong,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: jobs.isEmpty
                      ? const SingleChildScrollView(child: _EmptyState())
                      : _JobList(jobs: jobs),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n(I18nKey.homePhaseNotice),
                  style: theme.typography.caption?.copyWith(
                    color: resources.textFillColorTertiary,
                  ),
                  softWrap: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The "nothing queued yet" card.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    return _Card(
      padding: const EdgeInsetsDirectional.all(20),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              FluentIcons.document_24_regular,
              size: 28,
              color: theme.resources.textFillColorSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n(I18nKey.homeEmptyTitle),
              style: theme.typography.subtitle,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            const SizedBox(height: 6),
            Text(
              // Touch targets cannot receive a drop, so they get copy that
              // only mentions the picker.
              l10n(
                supportsDropTarget
                    ? I18nKey.homeEmptyBody
                    : I18nKey.homeEmptyBodyTouch,
              ),
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            const SizedBox(height: 8),
            Text(
              l10n(I18nKey.jobsEmpty),
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorTertiary,
              ),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            if (supportsDropTarget) ...<Widget>[
              const SizedBox(height: 16),
              const _DropHint(),
            ],
          ],
        ),
      ),
    );
  }
}

/// A quiet bordered strip repeating the drag-and-drop affordance.
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            FluentIcons.folder_24_regular,
            size: 14,
            color: theme.resources.textFillColorSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n(I18nKey.homeDropHintIdle),
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable list of queued and finished encodes.
class _JobList extends StatelessWidget {
  const _JobList({required this.jobs});

  final List<EncodeJob> jobs;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: jobs.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) =>
            JobRow(job: jobs[index]),
      ),
    );
  }
}

/// One task row: name, state, progress bar, pause/resume, long-press to stop.
class JobRow extends StatelessWidget {
  /// Creates a row for [job].
  const JobRow({super.key, required this.job});

  /// The job this row renders.
  final EncodeJob job;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    final double? progress = job.progress;

    return GestureDetector(
      onLongPress: job.isFinished ? null : () => _confirmStop(context),
      child: _Card(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      job.displayName,
                      style: theme.typography.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l10n(_stateKey(job.state))} · ${_positionText(job, l10n)}',
                      style: theme.typography.caption?.copyWith(
                        color: job.state == JobState.failed
                            ? resources.textFillColorSecondary
                            : resources.textFillColorTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    ProgressBar(
                      value: progress == null ? null : progress * 100,
                    ),
                    if (job.error != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        job.error!,
                        style: theme.typography.caption?.copyWith(
                          color: resources.textFillColorSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (job.state == JobState.running)
                Tooltip(
                  message: l10n(I18nKey.jobPause),
                  child: IconButton(
                    icon: const Icon(FluentIcons.pause_24_regular, size: 14),
                    onPressed: () async {
                      final bool paused = await JobQueue.instance.pause(job);
                      if (!paused && context.mounted) {
                        await showDialog<void>(
                          context: context,
                          builder: (BuildContext context) => ContentDialog(
                            title: Text(l10n(I18nKey.jobPause)),
                            content: Text(l10n(I18nKey.jobPauseUnsupported)),
                            actions: <Widget>[
                              FilledButton(
                                child: Text(l10n(I18nKey.actionClose)),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                )
              else if (job.state == JobState.paused ||
                  job.state == JobState.queued)
                Tooltip(
                  message: l10n(
                    job.state == JobState.paused
                        ? I18nKey.jobResume
                        : I18nKey.jobStart,
                  ),
                  child: IconButton(
                    icon: const Icon(FluentIcons.play_24_regular, size: 14),
                    onPressed: job.state == JobState.paused
                        ? () => JobQueue.instance.resume(job)
                        : null,
                  ),
                ),
              if (job.isFinished)
                Tooltip(
                  message: l10n(I18nKey.jobRemove),
                  child: IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 14),
                    onPressed: () => JobQueue.instance.remove(job),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _positionText(EncodeJob job, AppL10n l10n) {
    final Duration? total = job.duration;
    final String position = _format(job.position);
    if (total == null) {
      return position;
    }
    return '$position · ${_format(total)}';
  }

  static String _format(Duration duration) {
    final String minutes = duration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final String seconds = duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final int hours = duration.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  static String _stateKey(JobState state) => switch (state) {
    JobState.queued => I18nKey.jobStateQueued,
    JobState.running => I18nKey.jobStateRunning,
    JobState.paused => I18nKey.jobStatePaused,
    JobState.completed => I18nKey.jobStateCompleted,
    JobState.failed => I18nKey.jobStateFailed,
    JobState.cancelled => I18nKey.jobStateCancelled,
  };

  Future<void> _confirmStop(BuildContext context) async {
    final AppL10n l10n = context.l10n;
    final bool? stop = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => ContentDialog(
        title: Text(l10n(I18nKey.jobConfirmStopTitle)),
        content: Text(l10n(I18nKey.jobConfirmStopBody)),
        actions: <Widget>[
          Button(
            child: Text(l10n(I18nKey.actionCancel)),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: Text(l10n(I18nKey.jobConfirmStopConfirm)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if ((stop ?? false) && context.mounted) {
      await JobQueue.instance.cancel(job);
    }
  }
}

/// Flat card used by the empty state and the task rows.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ResourceDictionary resources = FluentTheme.of(context).resources;
    return Container(
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: resources.cardStrokeColorDefault),
      ),
      padding: padding,
      child: child,
    );
  }
}
