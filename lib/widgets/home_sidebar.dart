import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';

/// Preferred width of the sidebar in logical pixels.
///
/// The shell squeezes the content region by this much only when the window can
/// afford it; below that threshold the sidebar floats over the content at a
/// fraction of the window width instead.
const double kHomeSidebarWidth = 240;

/// Navigation rail of the home shell.
///
/// Drawn on its own solid layer, one step apart from the content region, with a
/// single selected row for Home. Selection is fixed to Home in this phase, so
/// the row is presentational: it answers hover and focus but performs no
/// navigation. The whole rail scrolls instead of overflowing when the window is
/// short, and its border follows the ambient [Directionality].
///
/// With [floating] set the rail is the narrow-window variant: it stands on the
/// higher layer fill so it reads as a panel above the content, and it takes
/// [width] instead of [kHomeSidebarWidth].
class HomeSidebar extends StatelessWidget {
  /// Creates the sidebar.
  const HomeSidebar({
    super.key,
    this.floating = false,
    this.width = kHomeSidebarWidth,
  });

  /// Whether the rail is floating above the content region.
  final bool floating;

  /// Width of the rail in logical pixels.
  final double width;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final AppL10n l10n = context.l10n;

    return Container(
      width: width,
      height: double.infinity,
      decoration: BoxDecoration(
        color: floating
            ? resources.solidBackgroundFillColorTertiary
            : resources.solidBackgroundFillColorSecondary,
        border: BorderDirectional(
          end: BorderSide(color: resources.controlStrokeColorDefault),
          start: floating
              ? BorderSide(color: resources.controlStrokeColorDefault)
              : BorderSide.none,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SidebarNavRow(
              icon: FluentIcons.list_24_filled,
              label: l10n(I18nKey.sidebarHome),
              selected: true,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 6),
              child: Text(
                l10n(I18nKey.homeSourcesTitle),
                style: theme.typography.bodyStrong?.copyWith(
                  color: resources.textFillColorSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
              child: Text(
                l10n(I18nKey.homeSourcesEmpty),
                style: theme.typography.caption?.copyWith(
                  color: resources.textFillColorTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 40 px navigation row with a WinUI-style selection indicator.
class _SidebarNavRow extends StatelessWidget {
  const _SidebarNavRow({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final Color accent = theme.accentColor.normal;

    return Semantics(
      selected: selected,
      child: SizedBox(
        height: 40,
        child: HoverButton(
          onPressed: () {},
          semanticLabel: label,
          builder: (BuildContext context, Set<WidgetState> states) {
            final bool hovered = states.contains(WidgetState.hovered);
            final bool pressed = states.contains(WidgetState.pressed);
            final Color background = selected
                ? accent.withValues(alpha: pressed ? 0.18 : 0.12)
                : pressed
                ? resources.subtleFillColorTertiary
                : hovered
                ? resources.subtleFillColorSecondary
                : const Color(0x00000000);

            return Container(
              padding: const EdgeInsetsDirectional.only(start: 8, end: 10),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: <Widget>[
                  // Reserved indicator slot, so the icon stays put whether the
                  // row is selected or not.
                  Container(
                    width: 3,
                    height: 16,
                    decoration: selected
                        ? BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(1.5),
                          )
                        : null,
                  ),
                  const SizedBox(width: 9),
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? accent : resources.textFillColorPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.typography.body?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
