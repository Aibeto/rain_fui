import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';

/// Shows one localized message with an optional raw platform detail.
///
/// [titleKey] and [messageKey] are i18n keys resolved against the active
/// locale. [detail] is data, not copy — typically the raw platform text of a
/// `FileSourceException` — so it is rendered below the message in a smaller
/// secondary style and never replaces the localized sentence. The dialog has a
/// single action that closes it.
Future<void> showMessageDialog(
  BuildContext context, {
  required String titleKey,
  required String messageKey,
  String? detail,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      final FluentThemeData theme = FluentTheme.of(context);
      final AppL10n l10n = context.l10n;
      final String? rawDetail = detail?.trim();
      final TextStyle detailStyle =
          (theme.typography.caption ?? const TextStyle()).copyWith(
            color: theme.resources.textFillColorSecondary,
          );
      return ContentDialog(
        title: Text(l10n(titleKey)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n(messageKey), softWrap: true),
            if (rawDetail != null && rawDetail.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(rawDetail, style: detailStyle, softWrap: true),
            ],
          ],
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
