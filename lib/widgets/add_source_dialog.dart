import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../services/file_source_service.dart';
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
    return await pick(context);
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
