import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../activities/language_activity.dart';
import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../services/theme_service.dart';

/// Height of the chrome bars, in logical pixels.
const double _barHeight = 48;

/// Fixed-height top bar of the shell: sidebar toggle, product name, language
/// picker and theme cycler.
///
/// Assembled by hand from a [Container] and a [Row] instead of a [Page] or
/// [ScaffoldPage], so the shell never drags in an acrylic backdrop (spec §2).
/// Layout follows the ambient [Directionality]: children are laid out from the
/// start edge, and the title takes the space that is left over.
class AppTopBar extends StatelessWidget {
  /// Creates the top bar.
  const AppTopBar({
    super.key,
    required this.onToggleSidebar,
    required this.sidebarVisible,
  });

  /// Shows or hides the sidebar.
  final VoidCallback onToggleSidebar;

  /// Whether the sidebar is currently visible; exposed to accessibility
  /// services as the toggle's `toggled` state.
  final bool sidebarVisible;

  /// Glyph that mirrors the current [ThemeMode].
  static IconData _iconFor(ThemeMode mode) => switch (mode) {
    ThemeMode.light => FluentIcons.weather_sunny_24_regular,
    ThemeMode.dark => FluentIcons.weather_moon_24_regular,
    ThemeMode.system => FluentIcons.desktop_24_regular,
  };

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ResourceDictionary resources = theme.resources;
    final ThemeService themeService = ThemeScope.of(context);
    final AppL10n l10n = context.l10n;

    return Container(
      height: _barHeight,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: resources.solidBackgroundFillColorBase,
        border: Border(
          bottom: BorderSide(color: resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: <Widget>[
          Semantics(
            toggled: sidebarVisible,
            child: Tooltip(
              message: l10n(I18nKey.topBarSidebarToggle),
              child: IconButton(
                icon: Icon(
                  FluentIcons.navigation_24_regular,
                  size: 16,
                  color: resources.textFillColorPrimary,
                ),
                onPressed: onToggleSidebar,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n(I18nKey.appTitle),
              // `Typography.titleLarge` is the 40/52 display step and cannot
              // fit a 48 px bar; the WinUI app-title size is 20/28.
              style: theme.typography.subtitle?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: l10n(I18nKey.topBarLanguage),
            child: IconButton(
              icon: Icon(
                FluentIcons.local_language_24_regular,
                size: 16,
                color: resources.textFillColorPrimary,
              ),
              onPressed: () =>
                  Navigator.of(context).push(LanguageActivity.route),
            ),
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeService.mode,
            builder: (BuildContext context, ThemeMode mode, Widget? child) {
              return Tooltip(
                message:
                    '${l10n(I18nKey.topBarTheme)} · '
                    '${l10n(ThemeService.labelKeyFor(mode))}',
                child: IconButton(
                  icon: Icon(
                    _iconFor(mode),
                    size: 16,
                    color: resources.textFillColorPrimary,
                  ),
                  onPressed: () => themeService.cycle(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
