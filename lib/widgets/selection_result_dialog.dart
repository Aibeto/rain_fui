import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../theme/app_theme.dart';

/// How many child names one folder renders before the list is cut short.
///
/// `FileSourceService` may already cap the listing; this keeps a pathological
/// folder from turning the dialog into an endless scroll.
const int _maxRenderedChildren = 50;

/// Shows the single result dialog for [selection] (spec §6.2 / §8).
///
/// The dialog is titled by [SourceSelection.titleKey] and renders whatever the
/// selection carries: file paths (or bare names when the platform hides them),
/// folders with their first-level children, per-folder read errors and the
/// notices the picker attached. Paths are selectable so the user can copy them.
Future<void> showSelectionResultDialog(
  BuildContext context,
  SourceSelection selection,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      final AppL10n l10n = context.l10n;
      return ContentDialog(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
        title: Text(l10n(selection.titleKey)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: _SelectionResultBody(selection: selection),
          ),
        ),
        actions: <Widget>[
          Button(
            child: Text(l10n(I18nKey.actionClose)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}

/// The scrollable part of the result dialog: files, folders, then notices.
class _SelectionResultBody extends StatelessWidget {
  const _SelectionResultBody({required this.selection});

  final SourceSelection selection;

  @override
  Widget build(BuildContext context) {
    final AppL10n l10n = context.l10n;
    if (selection.isEmpty) {
      return Text(l10n(I18nKey.resultNothing), softWrap: true);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (selection.files.isNotEmpty) ...<Widget>[
          _SectionHeader(l10n(I18nKey.resultFilesLabel)),
          const SizedBox(height: 4),
          for (final SelectedFile file in selection.files)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 4),
              child: SelectableText(
                file.display,
                style: _monoStyle(
                  context,
                  FluentTheme.of(context).typography.caption,
                ),
              ),
            ),
        ],
        if (selection.folders.isNotEmpty) ...<Widget>[
          if (selection.files.isNotEmpty) const SizedBox(height: 12),
          _SectionHeader(l10n(I18nKey.resultFoldersLabel)),
          for (final SelectedFolder folder in selection.folders)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8),
              child: _FolderBlock(folder: folder),
            ),
        ],
        if (selection.noticeKeys.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          for (final String noticeKey in selection.noticeKeys)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 4),
              child: Text(
                l10n(noticeKey),
                style: _secondaryStyle(context),
                softWrap: true,
              ),
            ),
        ],
      ],
    );
  }
}

/// A folder row: name, path, platform note, then its children or read error.
class _FolderBlock extends StatelessWidget {
  const _FolderBlock({required this.folder});

  final SelectedFolder folder;

  @override
  Widget build(BuildContext context) {
    final AppL10n l10n = context.l10n;
    final FluentThemeData theme = FluentTheme.of(context);
    final List<String> children = folder.children.length > _maxRenderedChildren
        ? folder.children.sublist(0, _maxRenderedChildren)
        : folder.children;
    final bool truncated =
        folder.truncated || children.length < folder.children.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(folder.name, style: theme.typography.bodyStrong, softWrap: true),
        const SizedBox(height: 2),
        Text(folder.path, style: _secondaryStyle(context), softWrap: true),
        if (folder.isWeb) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            l10n(I18nKey.resultWebPathsUnavailable),
            style: _secondaryStyle(context),
            softWrap: true,
          ),
        ],
        const SizedBox(height: 8),
        _SectionHeader(l10n(I18nKey.resultChildrenLabel)),
        const SizedBox(height: 2),
        if (folder.hasError) ...<Widget>[
          Text(l10n(I18nKey.resultReadError), softWrap: true),
          const SizedBox(height: 2),
          Text(
            folder.errorText!,
            style: _secondaryStyle(context),
            softWrap: true,
          ),
        ] else if (folder.children.isEmpty)
          Text(
            l10n(I18nKey.resultChildrenEmpty),
            style: _secondaryStyle(context),
            softWrap: true,
          )
        else ...<Widget>[
          for (final String child in children)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 2),
              child: Text(
                child,
                style: _monoStyle(context, theme.typography.caption),
                softWrap: true,
              ),
            ),
          if (truncated) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              l10n(I18nKey.resultChildrenTruncated),
              style: _secondaryStyle(context),
              softWrap: true,
            ),
          ],
        ],
      ],
    );
  }
}

/// Small semibold label that opens a result section.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: FluentTheme.of(context).typography.bodyStrong,
      softWrap: true,
    );
  }
}

/// Muted 12 px style for paths, notes and raw platform text.
TextStyle _secondaryStyle(BuildContext context) {
  final FluentThemeData theme = FluentTheme.of(context);
  return (theme.typography.caption ?? const TextStyle()).copyWith(
    color: theme.resources.textFillColorSecondary,
  );
}

/// Monospaced variant of [base], keeping the locale-specific font fallbacks.
TextStyle _monoStyle(BuildContext context, TextStyle? base) =>
    AppTheme.mono(base, context.l10n.locale);
