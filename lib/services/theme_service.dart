import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/i18n_keys.dart';

/// Lets callers name the theme mode without importing fluent_ui themselves.
export 'package:fluent_ui/fluent_ui.dart' show ThemeMode;

/// Owns the light → dark → system cycle from spec §3.1.
///
/// The chosen mode survives a restart under [prefKey]. A fresh install follows
/// the system, which is what [parse] returns for a missing or unknown value.
class ThemeService {
  ThemeService({ThemeMode initial = ThemeMode.system})
    : _mode = ValueNotifier<ThemeMode>(initial);

  /// Preferences key holding [ThemeMode] by name.
  static const String prefKey = 'app_theme';

  /// Reads the stored mode. Anything unexpected means "follow the system".
  static ThemeMode parse(String? stored) => switch (stored) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Mode to launch with, read before the first frame so the window does not
  /// paint light and then jump to dark.
  static Future<ThemeMode> loadStartupMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return parse(prefs.getString(prefKey));
  }

  static Future<void> _persist(ThemeMode mode) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, mode.name);
  }

  /// Cycle order. `ThemeMode` comes from `material_ui` re-exported by
  /// `fluent_ui`, which is also what `FluentApp.themeMode` expects.
  static const List<ThemeMode> order = <ThemeMode>[
    ThemeMode.light,
    ThemeMode.dark,
    ThemeMode.system,
  ];

  final ValueNotifier<ThemeMode> _mode;

  /// Feed this into `ValueListenableBuilder` around `FluentApp`.
  ValueListenable<ThemeMode> get mode => _mode;

  ThemeMode get value => _mode.value;

  /// Advances one step, writes the result and returns the new mode.
  ///
  /// The write is fire and forget: the UI must not wait on disk to repaint, and
  /// a failed write only costs the persisted choice.
  ThemeMode cycle() {
    final int index = order.indexOf(_mode.value);
    final ThemeMode next = order[(index + 1) % order.length];
    _mode.value = next;
    unawaited(_persist(next));
    return next;
  }

  /// i18n key of the label shown for [mode].
  static String labelKeyFor(ThemeMode mode) => switch (mode) {
    ThemeMode.light => I18nKey.themeLight,
    ThemeMode.dark => I18nKey.themeDark,
    ThemeMode.system => I18nKey.themeSystem,
  };

  /// i18n key of the label for the current mode.
  String get labelKey => labelKeyFor(_mode.value);

  void dispose() => _mode.dispose();
}

/// Makes the single [ThemeService] reachable from the top bar without threading
/// callbacks through every widget.
class ThemeScope extends InheritedWidget {
  const ThemeScope({super.key, required this.service, required super.child});

  final ThemeService service;

  static ThemeService of(BuildContext context) {
    final ThemeScope? scope = context
        .dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope above this widget.');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) => oldWidget.service != service;
}
