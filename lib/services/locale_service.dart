import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/i18n.dart';

/// Reads/writes the persisted language choice and resolves the startup locale.
///
/// The three startup rules of spec §1 live in [resolveStartupLocale], which is
/// pure so it can be reasoned about (and unit-tested) without touching
/// `SharedPreferences`.
abstract final class LocaleService {
  /// SharedPreferences key holding the user's explicit choice.
  static const String prefKey = 'app_locale';

  /// The persisted tag, or `null` when absent or not one of the 19 locales.
  ///
  /// A corrupt/unknown stored value is treated as "no choice" so the app still
  /// follows the system language instead of falling back to English forever.
  static Future<String?> readPersistedTag() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(prefKey);
    if (raw == null) {
      return null;
    }
    return supportedTagForLocale(localeForTag(raw));
  }

  /// Stores the user's choice. Does not apply it — see spec §4.
  static Future<void> persistTag(String tag) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, tag);
  }

  /// Spec §1, in order: persisted choice → supported system locale → en-US.
  static Locale resolveStartupLocale({
    String? persistedTag,
    Locale? systemLocale,
  }) {
    final String? persisted = persistedTag == null
        ? null
        : supportedTagForLocale(localeForTag(persistedTag));
    if (persisted != null) {
      return localeForTag(persisted);
    }
    if (systemLocale != null) {
      final String? system = supportedTagForLocale(systemLocale);
      if (system != null) {
        return localeForTag(system);
      }
    }
    return kFallbackLocale;
  }

  /// Platform locale without needing a `BuildContext`.
  static Locale get systemLocale => PlatformDispatcher.instance.locale;

  /// Startup entry point used by `main()`.
  static Future<Locale> loadStartupLocale({Locale? systemLocale}) async {
    final String? persisted = await readPersistedTag();
    return resolveStartupLocale(
      persistedTag: persisted,
      systemLocale: systemLocale ?? LocaleService.systemLocale,
    );
  }
}
