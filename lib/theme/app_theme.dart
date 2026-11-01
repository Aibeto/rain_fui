import 'package:fluent_ui/fluent_ui.dart';

/// Global typography and theme construction.
///
/// Two things are non-obvious here:
///
/// * `FluentThemeData` only accepts a single `fontFamily`, so the per-script
///   `fontFamilyFallback` chain is applied to every style of the `Typography`
///   ramp. That is what keeps CJK, Arabic and Thai from rendering as tofu while
///   Latin/Cyrillic stay on Source Sans 3 (spec §2.2).
/// * The fallback order is locale aware: a Traditional Chinese session puts
///   Noto Sans TC ahead of SC so Han unification picks the right glyph shapes.
abstract final class AppTheme {
  /// Primary humanist sans (OFL 1.1) — Latin, Greek, Cyrillic, Vietnamese.
  static const String fontFamily = 'Source Sans 3';

  /// Tabular face used by `LanguageActivity` so the language codes line up.
  static const String monoFamily = 'Source Code Pro';

  static const String notoSansSC = 'Noto Sans SC';
  static const String notoSansTC = 'Noto Sans TC';
  static const String notoSansJP = 'Noto Sans JP';
  static const String notoSansKR = 'Noto Sans KR';
  static const String notoSansArabic = 'Noto Sans Arabic';
  static const String notoSansThai = 'Noto Sans Thai';

  /// Default order used by every locale that has no CJK/Arabic/Thai script.
  static const List<String> fontFallback = <String>[
    notoSansSC,
    notoSansTC,
    notoSansJP,
    notoSansKR,
    notoSansArabic,
    notoSansThai,
  ];

  /// Fallback chain for [locale], script-relevant font first.
  static List<String> fallbackFor(Locale locale) {
    switch (locale.languageCode) {
      case 'zh':
        final bool traditional =
            locale.countryCode == 'TW' ||
            locale.countryCode == 'HK' ||
            locale.countryCode == 'MO';
        return traditional
            ? const <String>[
                notoSansTC,
                notoSansSC,
                notoSansJP,
                notoSansKR,
                notoSansArabic,
                notoSansThai,
              ]
            : const <String>[
                notoSansSC,
                notoSansTC,
                notoSansJP,
                notoSansKR,
                notoSansArabic,
                notoSansThai,
              ];
      case 'ja':
        return const <String>[
          notoSansJP,
          notoSansSC,
          notoSansTC,
          notoSansKR,
          notoSansArabic,
          notoSansThai,
        ];
      case 'ko':
        return const <String>[
          notoSansKR,
          notoSansJP,
          notoSansSC,
          notoSansTC,
          notoSansArabic,
          notoSansThai,
        ];
      case 'ar':
        return const <String>[
          notoSansArabic,
          notoSansSC,
          notoSansTC,
          notoSansJP,
          notoSansKR,
          notoSansThai,
        ];
      case 'th':
        return const <String>[
          notoSansThai,
          notoSansSC,
          notoSansTC,
          notoSansJP,
          notoSansKR,
          notoSansArabic,
        ];
      default:
        return fontFallback;
    }
  }

  static FluentThemeData light(Locale locale) =>
      _theme(Brightness.light, locale);

  static FluentThemeData dark(Locale locale) => _theme(Brightness.dark, locale);

  /// Page surface. Pure white and pure black on purpose: the Fluent defaults
  /// (#f3f3f3 / #202020) are close enough to the flyout and card fills that
  /// dropdown panels visually merge into the page behind them.
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color darkSurface = Color(0xFF000000);

  /// Bars and the docked sidebar. One step away from the page so the chrome
  /// reads as a frame instead of dissolving into the content.
  static const Color lightChrome = Color(0xFFF2F2F2);
  static const Color darkChrome = Color(0xFF161616);

  /// Cards and list rows: a raised step over the page in dark mode, plain white
  /// with a hairline border in light mode where shadow would be heavier than
  /// the Fluent look allows.
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color darkCard = Color(0xFF1C1C1C);

  /// Recessed areas such as the terminal body and the empty-state well.
  static const Color lightInset = Color(0xFFF7F7F7);
  static const Color darkInset = Color(0xFF0D0D0D);

  /// Progress bars: solid blue while the length is known, pale blue while it
  /// is not yet known.
  static const Color progressRunning = Color(0xFF0078D4);
  static const Color progressUnknown = Color(0xFF9EC9EC);

  static const Color lightBorder = Color(0xFFE3E3E3);
  static const Color darkBorder = Color(0xFF2E2E2E);

  /// Solid fill used by menus, combo-box popups and tooltips.
  static Color surfaceFor(Brightness brightness) =>
      brightness == Brightness.light ? lightSurface : darkSurface;

  static Color chromeFor(Brightness brightness) =>
      brightness == Brightness.light ? lightChrome : darkChrome;

  static Color cardFor(Brightness brightness) =>
      brightness == Brightness.light ? lightCard : darkCard;

  static Color insetFor(Brightness brightness) =>
      brightness == Brightness.light ? lightInset : darkInset;

  static Color borderFor(Brightness brightness) =>
      brightness == Brightness.light ? lightBorder : darkBorder;

  static FluentThemeData _theme(Brightness brightness, Locale locale) {
    final List<String> fallback = fallbackFor(locale);
    final Color surface = surfaceFor(brightness);
    return FluentThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: surface,
      micaBackgroundColor: surface,
      menuColor: surface,
      cardColor: cardFor(brightness),
      typography: _withFallback(
        Typography.fromBrightness(brightness: brightness),
        fallback,
      ),
    );
  }

  static Typography _withFallback(Typography source, List<String> fallback) {
    TextStyle? fix(TextStyle? style) =>
        style?.copyWith(fontFamily: fontFamily, fontFamilyFallback: fallback);
    return Typography.raw(
      display: fix(source.display),
      titleLarge: fix(source.titleLarge),
      title: fix(source.title),
      subtitle: fix(source.subtitle),
      bodyLarge: fix(source.bodyLarge),
      bodyStrong: fix(source.bodyStrong),
      body: fix(source.body),
      caption: fix(source.caption),
    );
  }

  /// Monospaced variant of [base] with tabular figures and the same script
  /// fallbacks, used for the language table.
  static TextStyle mono(TextStyle? base, Locale locale) {
    final TextStyle style = base ?? const TextStyle();
    return style.copyWith(
      fontFamily: monoFamily,
      fontFamilyFallback: fallbackFor(locale),
      fontFeatures: <FontFeature>[
        ...?style.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );
  }
}
