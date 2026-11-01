import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../services/file_source_service.dart';
import '../theme/app_theme.dart';
import 'message_dialog.dart';

/// The picker the user asked for in the "+" dialog.
enum _AddSourceChoice { files, folder }

/// Opens the "+" dialog, runs the chosen picker, reports picker failures in a
/// message dialog, and returns the selection (null when cancelled).
///
/// The picker runs with the caller's [context] after the dialog has closed, so
/// no dialog is left holding a dead context. Every [FileSourceException] —
/// including the web and Android folder cases — is surfaced as a localized
/// [showMessageDialog] with the raw platform text as secondary detail.
///
/// A picked folder gets one extra step before it is handed back: the user
/// confirms the folder, because a directory picker returns on a single click and
/// the folder brings its whole first level with it. Files need no such step —
/// the multi-select picker already ends with an explicit confirm action.
Future<SourceSelection?> showAddSourceDialog(BuildContext context) async {
  final _AddSourceChoice? choice = await showDialog<_AddSourceChoice>(
    context: context,
    builder: (BuildContext context) => const _AddSourceDialog(),
  );
  if (choice == null || !context.mounted) {
    return null;
  }
  final Future<SourceSelection?> Function(BuildContext context) pick =
      switch (choice) {
        _AddSourceChoice.files => FileSourceService.pickFiles,
        _AddSourceChoice.folder => FileSourceService.pickFolder,
      };
  try {
    final SourceSelection? selection = await pick(context);
    if (selection == null || !context.mounted) {
      return null;
    }
    if (choice == _AddSourceChoice.folder) {
      final bool confirmed = await _confirmFolder(context, selection);
      if (!confirmed) {
        return null;
      }
    }
    return selection;
  } on FileSourceException catch (error) {
    if (!context.mounted) {
      return null;
    }
    await showMessageDialog(
      context,
      titleKey: I18nKey.addSourceTitle,
      messageKey: error.messageKey,
      detail: error.detail,
    );
    return null;
  }
}

/// Asks whether the picked folder should really be added; false on dismiss.
Future<bool> _confirmFolder(
  BuildContext context,
  SourceSelection selection,
) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) =>
        _FolderConfirmDialog(selection: selection),
  );
  return confirmed ?? false;
}

/// Confirmation step for a picked folder: the path plus an explicit Add.
class _FolderConfirmDialog extends StatelessWidget {
  const _FolderConfirmDialog({required this.selection});

  final SourceSelection selection;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;
    final SelectedFolder? folder = selection.folders.isEmpty
        ? null
        : selection.folders.first;

    return ContentDialog(
      title: Text(l10n(I18nKey.addSourceConfirmTitle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n(I18nKey.addSourceConfirmBody), softWrap: true),
          if (folder != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              folder.name,
              style: theme.typography.bodyStrong,
              softWrap: true,
            ),
            const SizedBox(height: 2),
            SelectableText(
              folder.path,
              // Paths are the one place where a monospaced face helps: it keeps
              // separators readable and long names wrap predictably.
              style: AppTheme.mono(
                theme.typography.caption?.copyWith(
                  color: resources.textFillColorSecondary,
                ),
                l10n.locale,
              ),
              maxLines: 3,
            ),
          ],
        ],
      ),
      actions: <Widget>[
        Button(
          child: Text(l10n(I18nKey.actionCancel)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        FilledButton(
          child: Text(l10n(I18nKey.actionAdd)),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// The body of the "+" dialog: two large tiles and a cancel action.
class _AddSourceDialog extends StatelessWidget {
  const _AddSourceDialog();

  @override
  Widget build(BuildContext context) {
    final AppL10n l10n = context.l10n;
    return ContentDialog(
      title: Text(l10n(I18nKey.addSourceTitle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n(I18nKey.addSourceBody), softWrap: true),
          const SizedBox(height: 16),
          _AddSourceTile(
            icon: FluentIcons.document_24_regular,
            title: l10n(I18nKey.addSourceFiles),
            subtitle: l10n(I18nKey.addSourceFilesHint),
            onPressed: () => Navigator.of(context).pop(_AddSourceChoice.files),
          ),
          const SizedBox(height: 8),
          _AddSourceTile(
            icon: FluentIcons.folder_24_regular,
            title: l10n(I18nKey.addSourceFolder),
            subtitle: l10n(I18nKey.addSourceFolderHint),
            // Browsers have no directory picker. The tile is dimmed but stays
            // tappable: choosing it surfaces `error_folder_unsupported_web`
            // through the same message dialog the picker failures use.
            dimmed: kIsWeb,
            onPressed: () => Navigator.of(context).pop(_AddSourceChoice.folder),
          ),
        ],
      ),
      actions: <Widget>[
        Button(
          child: Text(l10n(I18nKey.actionCancel)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// A wide, tappable option row with an icon, a title and a hint line.
class _AddSourceTile extends StatelessWidget {
  const _AddSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.dimmed = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  /// Renders the tile with disabled colours while keeping it interactive.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color disabledColor = theme.resources.textFillColorDisabled;
    return Button(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12),
        ),
        foregroundColor: dimmed
            ? WidgetStatePropertyAll<Color>(disabledColor)
            : null,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Icon(icon, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.typography.bodyStrong?.copyWith(
                    color: dimmed ? disabledColor : null,
                  ),
                  softWrap: true,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.typography.caption?.copyWith(
                    color: dimmed
                        ? disabledColor
                        : theme.resources.textFillColorSecondary,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
