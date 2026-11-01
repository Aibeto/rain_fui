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
  /// Width at which the sidebar may start eating into the content region.
  ///
  /// Below this the sidebar floats above the content instead, because squeezing
  /// a narrow window would leave the content region unusable.
  static const double _pushSidebarBreakpoint = kHomeSidebarWidth + 600;

  /// Fraction of the window width the floating sidebar may cover.
  static const double _floatingSidebarMaxFraction = 0.85;

  /// The rail starts closed so the content region gets the whole window first.
  bool _sidebarVisible = false;
  SourceSelection? _selection;

  void _toggleSidebar() {
    setState(() => _sidebarVisible = !_sidebarVisible);
  }

  void _hideSidebar() {
    if (!_sidebarVisible) {
      return;
    }
    setState(() => _sidebarVisible = false);
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

  /// Builds the shell body: pushes the content aside when the window can afford
  /// a permanent rail, floats the rail above the content when it cannot.
  Widget _buildBody(BuildContext context, BoxConstraints constraints) {
    final Widget content = DropSurface(
      onSelection: _handleDroppedSelection,
      onError: _handleDropError,
      child: HomeContent(
        selection: _selection,
        onClearRequested: _selection == null ? null : _clearSelection,
      ),
    );

    if (constraints.maxWidth >= _pushSidebarBreakpoint) {
      return Row(
        children: <Widget>[
          if (_sidebarVisible) const HomeSidebar(),
          Expanded(child: content),
        ],
      );
    }

    final double widest = constraints.maxWidth * _floatingSidebarMaxFraction;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: content),
        if (_sidebarVisible) ...<Widget>[
          // Tapping the smoked area closes the floating rail, the same gesture
          // a modal pane would offer.
          Positioned.fill(child: _Scrim(onTap: _hideSidebar)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: HomeSidebar(
              floating: true,
              width: widest < kHomeSidebarWidth ? widest : kHomeSidebarWidth,
            ),
          ),
        ],
      ],
    );
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
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  _buildBody(context, constraints),
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

/// Dimming layer that turns a tap outside the floating sidebar into a dismiss.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ColoredBox(
        // Smoke fill is a plain translucent colour — no blur is involved, so it
        // stays within the no-blur rule.
        color: FluentTheme.of(context).resources.smokeFillColorDefault,
      ),
    );
  }
}
