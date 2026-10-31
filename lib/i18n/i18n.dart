import 'package:flutter/widgets.dart';

import 'ar.dart';
import 'de_DE.dart';
import 'en_GB.dart';
import 'en_US.dart';
import 'es_ES.dart';
import 'fr_FR.dart';
import 'id_ID.dart';
import 'it_IT.dart';
import 'ja_JP.dart';
import 'ko_KR.dart';
import 'nl_NL.dart';
import 'pl_PL.dart';
import 'pt_BR.dart';
import 'ru_RU.dart';
import 'th_TH.dart';
import 'tr_TR.dart';
import 'vi_VN.dart';
import 'zh_CN.dart';
import 'zh_TW.dart';

/// Canonical BCP-47 tags of the 19 supported locales, in the display order used
/// by `LanguageActivity` (spec §5.1). `ar` is the one locale without a region.
const List<String> kSupportedLanguageTags = <String>[
  'zh-CN',
  'zh-TW',
  'ja-JP',
  'ko-KR',
  'vi-VN',
  'th-TH',
  'id-ID',
  'en-US',
  'en-GB',
  'fr-FR',
  'de-DE',
  'es-ES',
  'it-IT',
  'pt-BR',
  'ru-RU',
  'nl-NL',
  'pl-PL',
  'ar',
  'tr-TR',
];

/// Locale forced whenever nothing better is available (spec §1, rule 3).
const String kFallbackTag = 'en-US';

/// `Locale` for [kFallbackTag].
const Locale kFallbackLocale = Locale('en', 'US');

/// Every catalog, keyed by its canonical tag.
const Map<String, Map<String, String>> kCatalogs =
    <String, Map<String, String>>{
      'zh-CN': zhCn,
      'zh-TW': zhTw,
      'ja-JP': jaJp,
      'ko-KR': koKr,
      'vi-VN': viVn,
      'th-TH': thTh,
      'id-ID': idId,
      'en-US': enUs,
      'en-GB': enGb,
      'fr-FR': frFr,
      'de-DE': deDe,
      'es-ES': esEs,
      'it-IT': itIt,
      'pt-BR': ptBr,
      'ru-RU': ruRu,
      'nl-NL': nlNl,
      'pl-PL': plPl,
      'ar': ar,
      'tr-TR': trTr,
    };

/// The 19 supported `Locale`s, in `LanguageActivity` order.
final List<Locale> kSupportedLocales = List<Locale>.unmodifiable(
  kSupportedLanguageTags.map(localeForTag),
);

/// Builds a [Locale] from `zh-CN`, `zh_CN` or `ar` style tags.
Locale localeForTag(String tag) {
  final List<String> parts = tag
      .replaceAll('_', '-')
      .split('-')
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return kFallbackLocale;
  }
  final String languageCode = parts.first.toLowerCase();
  if (parts.length == 1) {
    return Locale(languageCode);
  }
  final String second = parts[1];
  // A four-letter subtag is a script ("Hant"), not a region.
  if (second.length == 4) {
    return Locale.fromSubtags(
      languageCode: languageCode,
      scriptCode: _capitalize(second),
      countryCode: parts.length > 2 ? parts[2].toUpperCase() : null,
    );
  }
  return Locale(languageCode, second.toUpperCase());
}

/// Canonical tag for [locale], e.g. `Locale('zh', 'TW')` → `zh-TW`.
String tagForLocale(Locale locale) {
  final List<String> chunks = <String>[
    locale.languageCode.toLowerCase(),
    if (locale.countryCode != null && locale.countryCode!.isNotEmpty)
      locale.countryCode!.toUpperCase(),
  ];
  return chunks.join('-');
}

String _capitalize(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';

/// Maps an arbitrary system [locale] onto one of the 19 supported tags.
///
/// Resolution order: exact language+region → same language with a sensible
/// default region → `null` (caller falls back to English).
String? supportedTagForLocale(Locale locale) {
  final String language = locale.languageCode.toLowerCase();
  if (language.isEmpty) {
    return null;
  }
  final String? region =
      (locale.countryCode == null || locale.countryCode!.isEmpty)
      ? null
      : locale.countryCode!.toUpperCase();

  // 1. Exact match on language + region.
  for (final String tag in kSupportedLanguageTags) {
    final Locale candidate = localeForTag(tag);
    if (candidate.languageCode == language &&
        candidate.countryCode != null &&
        candidate.countryCode == region) {
      return tag;
    }
  }

  // 2. Same language, default region. Only for languages we actually ship;
  //    `zh`, `en` and `pt` have more than one supported region, so the script
  //    or region decides.
  switch (language) {
    case 'zh':
      final bool traditional =
          locale.scriptCode == 'Hant' ||
          region == 'TW' ||
          region == 'HK' ||
          region == 'MO';
      return traditional ? 'zh-TW' : 'zh-CN';
    case 'en':
      return region == 'GB' ? 'en-GB' : 'en-US';
    case 'pt':
      return 'pt-BR';
    case 'ar':
      return 'ar';
    case 'ja':
      return 'ja-JP';
    case 'ko':
      return 'ko-KR';
    case 'vi':
      return 'vi-VN';
    case 'th':
      return 'th-TH';
    case 'id':
      return 'id-ID';
    case 'fr':
      return 'fr-FR';
    case 'de':
      return 'de-DE';
    case 'es':
      return 'es-ES';
    case 'it':
      return 'it-IT';
    case 'ru':
      return 'ru-RU';
    case 'nl':
      return 'nl-NL';
    case 'pl':
      return 'pl-PL';
    case 'tr':
      return 'tr-TR';
  }
  return null;
}

/// Catalog for [tag], or the English catalog when [tag] is unknown.
Map<String, String> catalogForTag(String tag) =>
    kCatalogs[tag] ?? kCatalogs[kFallbackTag]!;

/// Catalog for [locale], resolved through [supportedTagForLocale].
Map<String, String> catalogForLocale(Locale locale) =>
    catalogForTag(supportedTagForLocale(locale) ?? kFallbackTag);

/// The lookup described in spec §5.2: primary catalog → `en_US` → the key
/// itself, so a missing translation is visible instead of crashing.
String translate(String key, Locale locale) {
  final Map<String, String> primary = catalogForLocale(locale);
  final String? value = primary[key];
  if (value != null) {
    return value;
  }
  final String? fallback = kCatalogs[kFallbackTag]![key];
  return fallback ?? key;
}

/// Translation facade handed to widgets through [I18nScope].
class AppL10n {
  const AppL10n(this.locale);

  final Locale locale;

  String call(String key) => translate(key, locale);

  String get tag => supportedTagForLocale(locale) ?? kFallbackTag;

  bool get isRtl => locale.languageCode == 'ar' || locale.languageCode == 'he';

  @override
  bool operator ==(Object other) => other is AppL10n && other.locale == locale;

  @override
  int get hashCode => locale.hashCode;
}

/// Publishes the fixed startup locale to the whole tree. The locale does not
/// change at runtime in this phase (see spec §4), so this is a plain inherited
/// widget rather than a stateful source.
class I18nScope extends InheritedWidget {
  const I18nScope({super.key, required this.l10n, required super.child});

  final AppL10n l10n;

  static AppL10n of(BuildContext context) {
    final I18nScope? scope = context
        .dependOnInheritedWidgetOfExactType<I18nScope>();
    assert(scope != null, 'No I18nScope above this widget.');
    return scope?.l10n ?? const AppL10n(kFallbackLocale);
  }

  @override
  bool updateShouldNotify(I18nScope oldWidget) => oldWidget.l10n != l10n;
}

extension L10nContext on BuildContext {
  /// `context.l10n(I18nKey.homeTitle)`
  AppL10n get l10n => I18nScope.of(this);
}
