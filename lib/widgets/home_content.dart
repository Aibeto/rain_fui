import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../services/platform_support.dart';
import '../theme/app_theme.dart';

/// Main content region of the home shell.
///
/// With no [selection] it shows the empty state: what to do next and the
/// reminder that nothing is wired to FFmpeg yet. Once a source has been added it
/// summarises what was picked, so the content region keeps the last result on
/// screen after the result dialog is dismissed. [onClearRequested] is null when
/// there is nothing to clear.
///
/// There is no page heading on purpose: the window title in the top bar already
/// names the app, so the region starts with the state instead of a label.
class HomeContent extends StatelessWidget {
  /// Creates the content region.
  const HomeContent({super.key, this.selection, this.onClearRequested});

  /// The most recent selection, or null when nothing has been added yet.
  final SourceSelection? selection;

  /// Clears [selection]; null hides the clear affordance.
  final VoidCallback? onClearRequested;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    final SourceSelection? current = selection;

    return ColoredBox(
      color: resources.layerFillColorDefault,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 560,
                    maxHeight: 420,
                  ),
                  child: current == null
                      // Scroll instead of overflowing when the window is
                      // shorter than the empty-state card.
                      ? const SingleChildScrollView(child: _EmptyState())
                      : _SelectionSummary(
                          selection: current,
                          onClearRequested: onClearRequested,
                        ),
                ),
              ),
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
        ),
      ),
    );
  }
}

/// The "nothing added yet" card.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final AppL10n l10n = context.l10n;
    return _Card(
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
              style: theme.typography.bodyStrong?.copyWith(fontSize: 16),
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

/// Summary of the last selection, scrollable so long path lists stay inside the
/// card instead of overflowing the content region.
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.selection, this.onClearRequested});

  final SourceSelection selection;
  final VoidCallback? onClearRequested;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    final TextStyle? secondary = theme.typography.caption?.copyWith(
      color: resources.textFillColorSecondary,
    );
    final TextStyle mono = AppTheme.mono(secondary, l10n.locale);

    return _Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n(I18nKey.homeSourcesTitle),
                    style: theme.typography.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onClearRequested != null)
                  Tooltip(
                    message: l10n(I18nKey.actionClose),
                    child: IconButton(
                      icon: Icon(
                        FluentIcons.dismiss_24_regular,
                        size: 14,
                        color: resources.textFillColorSecondary,
                      ),
                      onPressed: onClearRequested,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.only(end: 8, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (selection.files.isNotEmpty) ...<Widget>[
                      _GroupLabel(l10n(I18nKey.resultFilesLabel)),
                      for (final SelectedFile file in selection.files)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(bottom: 2),
                          child: Text(
                            file.display,
                            style: mono,
                            softWrap: true,
                          ),
                        ),
                    ],
                    if (selection.folders.isNotEmpty) ...<Widget>[
                      _GroupLabel(l10n(I18nKey.resultFoldersLabel)),
                      for (final SelectedFolder folder in selection.folders)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                folder.name,
                                style: theme.typography.bodyStrong,
                                softWrap: true,
                              ),
                              Text(folder.path, style: mono, softWrap: true),
                            ],
                          ),
                        ),
                    ],
                    for (final String noticeKey in selection.noticeKeys)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(top: 6),
                        child: Text(
                          l10n(noticeKey),
                          style: secondary,
                          softWrap: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small caps-ish label that opens a group of entries.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4, bottom: 4),
      child: Text(
        label,
        style: theme.typography.caption?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.resources.textFillColorSecondary,
        ),
      ),
    );
  }
}

/// The one card style shared by the empty state and the summary.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: child,
    );
  }
}
