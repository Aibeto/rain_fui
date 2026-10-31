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

  static FluentThemeData _theme(Brightness brightness, Locale locale) {
    final List<String> fallback = fallbackFor(locale);
    return FluentThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
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
