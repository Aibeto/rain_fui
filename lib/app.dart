import 'package:fluent_ui/fluent_ui.dart';

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import 'activities/startup_activity.dart';

/// Root widget: fixed startup locale, theme cycle, and the i18n scope every
/// screen reads from.
///
/// The locale is resolved once in `main()` (spec §1) and intentionally never
/// changes at runtime, so it is passed in and never mutated.
class RainFuiApp extends StatefulWidget {
  const RainFuiApp({super.key, required this.initialLocale, this.themeService});

  final Locale initialLocale;

  /// Injected in tests; the app creates its own otherwise.
  final ThemeService? themeService;

  @override
  State<RainFuiApp> createState() => _RainFuiAppState();
}

class _RainFuiAppState extends State<RainFuiApp> {
  late final ThemeService _theme = widget.themeService ?? ThemeService();

  @override
  void dispose() {
    if (widget.themeService == null) {
      _theme.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l10n = AppL10n(widget.initialLocale);
    return I18nScope(
      l10n: l10n,
      child: ThemeScope(
        service: _theme,
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: _theme.mode,
          builder: (BuildContext context, ThemeMode mode, Widget? _) {
            return FluentApp(
              title: l10n(I18nKey.appTitle),
              locale: widget.initialLocale,
              supportedLocales: kSupportedLocales,
              theme: AppTheme.light(widget.initialLocale),
              darkTheme: AppTheme.dark(widget.initialLocale),
              themeMode: mode,
              // Explicit directionality so Arabic mirrors the whole shell even
              // if a localization delegate resolves late.
              builder: (BuildContext context, Widget? child) => Directionality(
                textDirection: l10n.isRtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child ?? const SizedBox.shrink(),
              ),
              home: const StartupActivity(),
            );
          },
        ),
      ),
    );
  }
}
