import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import 'add_source_dialog.dart';
import 'selection_result_dialog.dart';
import '../activities/media_job_activity.dart';

/// Height of the chrome bars, in logical pixels.
const double _barHeight = 48;

/// Fixed-height bottom bar of the shell.
///
/// Three equal slots keep the "+" action geometrically centred: the Home
/// destination on one side, add-source in the middle and an invisible spacer on
/// the other (spec §3.2). Layout is direction-aware, so the whole bar mirrors
/// under RTL locales.
class AppBottomBar extends StatelessWidget {
  /// Creates the bottom bar.
  const AppBottomBar({super.key, this.onSelection});

  /// Called with the selection the add-source flow produced, if any.
  final ValueChanged<SourceSelection>? onSelection;

  Future<void> _addSource(BuildContext context) async {
    final SourceSelection? selection = await showAddSourceDialog(context);
    if (selection == null || !context.mounted) {
      return;
    }
    onSelection?.call(selection);
    if (selection.folders.isEmpty && selection.files.length == 1) {
      await Navigator.of(context)
          .push(MediaJobActivity.route(selection.files.single));
      return;
    }
    await showSelectionResultDialog(context, selection);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;

    return Container(
      height: _barHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Center(
              child: Semantics(
                selected: true,
                child: Tooltip(
                  message: l10n(I18nKey.bottomBarHome),
                  child: IconButton(
                    icon: Icon(
                      FluentIcons.list_24_filled,
                      size: 16,
                      color: theme.accentColor.normal,
                    ),
                    // Home is the only destination in this phase, so the
                    // button keeps its selected look and does nothing.
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Tooltip(
                message: l10n(I18nKey.bottomBarAdd),
                child: IconButton(
                  icon: Icon(
                    FluentIcons.add_24_regular,
                    size: 18,
                    color: resources.textFillColorPrimary,
                  ),
                  onPressed: () => _addSource(context),
                ),
              ),
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
