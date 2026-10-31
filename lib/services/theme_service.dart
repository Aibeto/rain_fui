import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../i18n/i18n_keys.dart';

/// Owns the light → dark → system cycle from spec §3.1.
///
/// Persistence is explicitly out of scope for this phase, so the mode resets to
/// light on every launch.
class ThemeService {
  ThemeService({ThemeMode initial = ThemeMode.light})
    : _mode = ValueNotifier<ThemeMode>(initial);

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

  /// Advances one step and returns the new mode.
  ThemeMode cycle() {
    final int index = order.indexOf(_mode.value);
    final ThemeMode next = order[(index + 1) % order.length];
    _mode.value = next;
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
