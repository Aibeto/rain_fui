import 'package:fluent_ui/fluent_ui.dart';

import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import '../services/file_source_service.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/drop_surface.dart';
import '../widgets/home_content.dart';
import '../widgets/home_sidebar.dart';
import '../widgets/message_dialog.dart';
import '../widgets/selection_result_dialog.dart';
import '../widgets/top_bar.dart';

/// The home screen: top bar, collapsible sidebar, content region and the
/// bottom bar.
///
/// The shell is assembled by hand instead of with `ScaffoldPage` for two
/// reasons: the bottom bar has to be a full-bleed bar at the very bottom of the
/// safe area (a page footer would be inset), and Fluent's page materials drag in
/// an acrylic backdrop, which this UI forbids (spec §0).
///
/// This activity owns the only two pieces of view state in the shell — whether
/// the sidebar is open and the last [SourceSelection] — because both are shared
/// by the top bar, the sidebar, the content region and the bottom bar.
class HomeActivity extends StatefulWidget {
  /// Creates the home screen.
  const HomeActivity({super.key});

  @override
  State<HomeActivity> createState() => _HomeActivityState();
}

class _HomeActivityState extends State<HomeActivity> {
  bool _sidebarVisible = true;
  SourceSelection? _selection;

  void _toggleSidebar() {
    setState(() => _sidebarVisible = !_sidebarVisible);
  }

  /// Keeps the last selection on screen. The bottom bar shows its own result
  /// dialog, so this only stores state.
  void _rememberSelection(SourceSelection selection) {
    setState(() => _selection = selection);
  }

  /// Drops are stored and then reported through the same result dialog the
  /// pickers use (spec §8).
  Future<void> _handleDroppedSelection(SourceSelection selection) async {
    _rememberSelection(selection);
    if (!mounted) {
      return;
    }
    await showSelectionResultDialog(context, selection);
  }

  Future<void> _handleDropError(FileSourceException error) async {
    if (!mounted) {
      return;
    }
    await showMessageDialog(
      context,
      titleKey: I18nKey.resultDropTitle,
      messageKey: error.messageKey,
      detail: error.detail,
    );
  }

  void _clearSelection() {
    setState(() => _selection = null);
  }

  @override
  Widget build(BuildContext context) {
    final ResourceDictionary resources = FluentTheme.of(context).resources;

    return ColoredBox(
      // Painted first so the safe-area insets above and below the bars carry the
      // bar colour instead of a lighter page tint.
      color: resources.solidBackgroundFillColorBase,
      child: Column(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: AppTopBar(
              onToggleSidebar: _toggleSidebar,
              sidebarVisible: _sidebarVisible,
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                if (_sidebarVisible) const HomeSidebar(),
                Expanded(
                  child: DropSurface(
                    onSelection: _handleDroppedSelection,
                    onError: _handleDropError,
                    child: HomeContent(
                      selection: _selection,
                      onClearRequested: _selection == null
                          ? null
                          : _clearSelection,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: AppBottomBar(onSelection: _rememberSelection),
          ),
        ],
      ),
    );
  }
}
