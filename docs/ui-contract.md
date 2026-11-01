# Rain FUI — UI layer contract

This file is the single source of truth for the module boundaries, the i18n key
set, and the icon/font policy. Read it before editing UI code.

## Hard rules

1. **No blur, anywhere.** No `BackdropFilter`, no `ImageFilter.blur`, no
   `Acrylic`, no `BackdropGroup`. A translucent *solid* `Color` is fine.
2. **No hardcoded user-visible copy** outside `LanguageActivity`. Every label,
   tooltip, dialog title, empty state and error message is looked up through
   `context.l10n` (see `lib/i18n/i18n.dart`).
3. **Icons** come from `fluentui_system_icons` only. Import idiom:
   ```dart
   import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
   import 'package:fluentui_system_icons/fluentui_system_icons.dart';
   ```
   The `hide` clause matters: both packages export a class named `FluentIcons`.
4. **Components** come from `fluent_ui` (`Button`, `FilledButton`, `IconButton`,
   `ContentDialog`, `InfoBar`, `TextBox`, `Tooltip`, …).
5. This phase has **no FFmpeg/media logic**. `lib/src/ffmpeg/` is pre-existing
   plumbing from an earlier phase and must not be wired into the UI yet.

## Module map

```
lib/
├── main.dart                       entrypoint: bootstrap + runApp        [lead]
├── app.dart                        FluentApp, themes, locale, i18n scope [lead]
├── theme/app_theme.dart            FluentThemeData + font fallback       [lead]
├── models/source_selection.dart    data carried from pickers/drop → dialog [lead]
├── src/media/                      codec + container capability table    [lead]
│   ├── media_kind.dart             extension → video/audio/image
│   ├── option_spec.dart            sealed option descriptions
│   ├── codec_spec.dart             one encoder + its options
│   ├── container_spec.dart         one muxer + what it accepts
│   ├── capabilities.dart           lookups and compatibility filters
│   ├── capabilities_data.dart      the table itself
│   └── encode_request.dart         frozen form state → argv
├── i18n/
│   ├── i18n_keys.dart              frozen key constants                  [lead]
│   ├── i18n.dart                   registry + lookup + scope + extension [lead]
│   ├── en_US.dart                  reference catalog (most complete)     [lead]
│   └── <18 other catalogs>         one per locale, same keys             [i18n-*]
├── services/
│   ├── locale_service.dart         SharedPreferences + startup resolution[lead]
│   ├── theme_service.dart          ValueNotifier<ThemeMode> cycle        [lead]
│   ├── font_license_service.dart   LicenseRegistry OFL registration      [lead]
│   ├── file_source_service.dart    pickers, folder listing, drop mapping [lead]
│   ├── job_queue.dart              serial encode queue, progress, pause  [lead]
│   ├── platform_support.dart       supportsDropTarget (desktop + web only) [lead]
│   ├── child_listing.dart          name list + truncation flag             [lead]
│   └── directory_lister.dart       conditional dart:io / web stub          [lead]
│   └── android_permission_service.dart  notification/all-files skeleton  [dialogs]
├── activities/
│   ├── home_activity.dart          app shell + drop target               [lead]
│   ├── media_job_activity.dart     single-file encode form               [lead]
│   ├── job_log_activity.dart       terminal output of one job             [lead]
│   └── language_activity.dart      English-only locale list              [lead]
└── widgets/
    ├── top_bar.dart                AppTopBar                              [lead]
    ├── bottom_bar.dart             AppBottomBar                           [lead]
    ├── home_sidebar.dart           HomeSidebar                            [lead]
    ├── home_content.dart           HomeContent + JobRow (tap opens the log) [lead]
    ├── drop_surface.dart           DropTarget wrapper + drop overlay      [lead]
    ├── add_source_dialog.dart      the "+" ContentDialog                  [dialogs]
    ├── selection_result_dialog.dart  shared result ContentDialog          [dialogs]
    └── message_dialog.dart         localized error/notice dialog          [dialogs]
```

## Frozen public API

Everything below exists as written; treat the signatures as fixed so new code
keeps compiling against it.

```dart
// lib/i18n/i18n.dart
const List<String> kSupportedLanguageTags;        // 19 tags, spec display order
const String kFallbackTag = 'en-US';
const Locale kFallbackLocale;                     // Locale('en', 'US')
final List<Locale> kSupportedLocales;
Locale localeForTag(String tag);                  // 'zh-CN' / 'zh_CN' / 'ar'
String tagForLocale(Locale locale);
String? supportedTagForLocale(Locale locale);     // normalization + match
Map<String, String> catalogForLocale(Locale locale);
String translate(String key, Locale locale);       // primary → en-US → key
class AppL10n { const AppL10n(Locale locale); String call(String key);
  String get tag; bool get isRtl; }
class I18nScope extends InheritedWidget { static AppL10n of(BuildContext); }
extension L10nContext on BuildContext { AppL10n get l10n; }
// usage: context.l10n(I18nKey.homeTitle)

// lib/i18n/i18n_keys.dart
abstract final class I18nKey { static const String appTitle = 'app_title'; … }

// lib/theme/app_theme.dart
abstract final class AppTheme {
  static const String fontFamily = 'Source Sans 3';
  static const String monoFamily = 'Source Code Pro';
  static const List<String> fontFallback;                  // SC,TC,JP,KR,AR,TH
  static List<String> fallbackFor(Locale locale);          // script-first order
  static FluentThemeData light(Locale locale);
  static FluentThemeData dark(Locale locale);
  static TextStyle mono(TextStyle? base, Locale locale);   // tabular figures
}

// lib/models/source_selection.dart
enum SourceOrigin { filePicker, folderPicker, drop }
class SelectedFile { final String name; final String? path;
  bool get hasPath; String get display; }
class SelectedFolder { final String name; final String path;
  final List<String> children; final bool truncated; final bool isWeb;
  final String? errorText; bool get hasError; }
class SourceSelection {
  final SourceOrigin origin; final List<SelectedFile> files;
  final List<SelectedFolder> folders; final List<String> noticeKeys;
  bool get isEmpty; int get itemCount; String get titleKey; }

// lib/services/file_source_service.dart
class FileSourceException implements Exception {
  final String messageKey; final String? detail;
  String localize(BuildContext context); }
abstract final class FileSourceService {
  static const int maxListedChildren = 200;
  static Future<SourceSelection?> pickFiles(BuildContext context);
  static Future<SourceSelection?> pickFolder(BuildContext context);
  static Future<SourceSelection?> selectionFromDrop(DropDoneDetails details);
  static Future<SelectedFolder> folderFromPath(String path); // never throws
}
// lib/services/directory_lister.dart
Future<ChildListing> listChildNames(String path, {int limit = 200});

// lib/services/theme_service.dart
class ThemeService { ThemeService({ThemeMode initial = ThemeMode.light});
  static const List<ThemeMode> order;               // light, dark, system
  ValueListenable<ThemeMode> get mode; ThemeMode get value;
  ThemeMode cycle(); String get labelKey;
  static String labelKeyFor(ThemeMode mode); void dispose(); }
class ThemeScope extends InheritedWidget { static ThemeService of(BuildContext); }

// lib/services/locale_service.dart
abstract final class LocaleService {
  static const String prefKey = 'app_locale';
  static Future<String?> readPersistedTag();
  static Future<void> persistTag(String tag);
  static Locale resolveStartupLocale({String? persistedTag, Locale? systemLocale});
  static Locale get systemLocale;
  static Future<Locale> loadStartupLocale({Locale? systemLocale});
}

// lib/services/font_license_service.dart
abstract final class FontLicenseService { static void register(); }

// lib/widgets/add_source_dialog.dart                                  [dialogs]
/// Opens the "+" dialog, runs the chosen picker, reports picker failures in a
/// message dialog, and returns the selection (null when cancelled).
Future<SourceSelection?> showAddSourceDialog(BuildContext context);

// lib/widgets/selection_result_dialog.dart                            [dialogs]
/// The single result dialog of spec §6.2 / §8.
Future<void> showSelectionResultDialog(
    BuildContext context, SourceSelection selection);

// lib/widgets/message_dialog.dart                                     [dialogs]
/// Localized single-message dialog (errors, unsupported-platform notes).
Future<void> showMessageDialog(
  BuildContext context, {
  required String titleKey,
  required String messageKey,
  String? detail,          // raw platform text, appended after the message
});

// lib/services/android_permission_service.dart                        [dialogs]
abstract final class AndroidPermissionService {
  static Future<bool> requestNotificationPermission();  // true when granted
  static Future<void> openManageAllFilesSettings();
}

// lib/activities/language_activity.dart                                [lead]
class LanguageActivity extends StatefulWidget { const LanguageActivity({super.key}); }
static Route<void> get route;  // FluentPageRoute<void>, used by the top bar

// lib/activities/home_activity.dart                                    [lead]
class HomeActivity extends StatefulWidget { const HomeActivity({super.key}); }

// lib/widgets/top_bar.dart                                             [lead]
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.onToggleSidebar,
    required this.sidebarVisible});
}

// lib/widgets/bottom_bar.dart                                          [lead]
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, this.onSelection});
  /// Notified after a successful pick, in addition to the result dialog that
  /// the bar itself shows. Null is fine — the dialog is the deliverable.
  final ValueChanged<SourceSelection>? onSelection;
}

// lib/widgets/home_sidebar.dart                                        [lead]
const double kHomeSidebarWidth = 240;
class HomeSidebar extends StatelessWidget {
  const HomeSidebar({super.key, this.floating = false,
    this.width = kHomeSidebarWidth});
  /// Narrow-window variant: stands on the higher layer fill and overlays the
  /// content region instead of squeezing it.
  final bool floating;
  final double width;
}

// lib/widgets/home_content.dart                                        [lead]
class HomeContent extends StatelessWidget {
  const HomeContent({super.key, this.selection, this.onClearRequested});
  final SourceSelection? selection;
  final VoidCallback? onClearRequested;
}

// lib/widgets/drop_surface.dart                                        [lead]
class DropSurface extends StatefulWidget {
  const DropSurface({super.key, required this.child,
    required this.onSelection, required this.onError});
  final Widget child;
  final ValueChanged<SourceSelection> onSelection;
  final ValueChanged<FileSourceException> onError;
}
```

The `+` flow is: `showAddSourceDialog` (picker, plus a confirm step for a
folder) → `showSelectionResultDialog`. The drop flow is: `DropSurface` →
`FileSourceService.selectionFromDrop` → `showSelectionResultDialog`, with
`FileSourceException` going to `showMessageDialog`.

## Encode flow

A pick that yields exactly one file (picker or drop) opens `MediaJobActivity`
instead of the result dialog; multi-file and folder picks keep the dialog. The
form starts from `detectMediaKind(fileName)`, offers the video encoder, audio
encoder and container that the static table says can work together, renders
`OptionSpec`s as widgets, and hands the frozen `EncodeRequest` to
`JobQueue.instance`, which runs one job at a time through the FFmpeg backend and
reports progress back to the home list. Pause is a real `SIGSTOP` on POSIX; when
the platform cannot signal a process the job says so instead of pretending.

## Layout behaviour

- The sidebar starts collapsed. `HomeActivity` pushes the content region aside
  only when the window is at least `kHomeSidebarWidth + 600` wide; below that it
  overlays the content with a smoked scrim that dismisses it on tap.
- Drop affordances (the static hint pill, the drag-hover overlay, the drop
  wording of the empty state) exist only where dragging does:
  `supportsDropTarget` = web, Windows, Linux, macOS. Touch platforms get their
  own copy and never see a hint.
- The home region has no page heading: the empty state or the source summary is
  the first thing under the top bar.

## i18n keys (frozen)

`app_title` `top_bar_sidebar_toggle` `top_bar_language` `top_bar_theme`
`theme_light` `theme_dark` `theme_system` `sidebar_home` `home_empty_title`
`home_empty_body` `home_empty_body_touch` `home_drop_hint` `home_drop_hint_idle`
`home_phase_notice` `home_sources_title` `home_sources_empty` `bottom_bar_home`
`bottom_bar_add` `add_source_title` `add_source_body` `add_source_files`
`add_source_files_hint` `add_source_folder` `add_source_folder_hint`
`add_source_confirm_title` `add_source_confirm_body` `action_add`
`action_cancel` `action_close` `result_files_title` `result_folder_title`
`result_drop_title` `result_nothing` `result_files_label` `result_folders_label`
`result_children_label` `result_children_empty` `result_children_truncated`
`result_web_paths_unavailable` `result_read_error` `error_picker_failed`
`error_folder_unsupported_web` `error_folder_unsupported_android`
`error_drop_failed`

Sentences are written for a plain `Map<String, String>`: **no placeholder
tokens**. Never concatenate translated fragments except with `' · '` or `': '`.

## API deviations forced by package versions

The spec quotes two package APIs that no longer exist in the versions that
resolve for this SDK. Both substitutions keep the behaviour the spec asks for.

1. **`file_picker` 13.3.0** removed `FilePicker.platform`; every entry point is
   static. Multi-select is `FilePicker.pickFiles(...)` — there is no
   `allowMultiple` flag, `pickFile(...)` is the single-file variant.
   `FilePicker.getDirectoryPath(...)` is unchanged.
2. **`desktop_drop` 0.8.4** — 0.9.x depends on `cross_file ^0.4.0`, which
   conflicts with `file_picker >= 12` (`cross_file ^0.3.5+4`), so version
   solving fails. In 0.8.4 the drop surface is `DropTarget(onDragDone: ...)`
   with a `DropDoneDetails.files` list of `DropItemFile` / `DropItemDirectory`
   (a directory carries its own `children`); there is no `acceptedKinds`, no
   `onDrop`, no `details.items` and no `DropItemKind`. `DropTarget` accepts
   files and directories alike, so both required kinds are covered.

## Notes for reviewers

- LanguageActivity is intentionally English-only and may hardcode its strings
  (including endonyms). It renders its list with a bundled monospace face so
  the language codes line up like a table; non-Latin endonyms fall back per
  script.
- The theme button tooltip is composed as `top_bar_theme` + `' · '` + the
  current mode label (`theme_light` / `theme_dark` / `theme_system`).
- `dart analyze` plus the two `tool/check_*.py` scripts are the only
  verification allowed: this phase must not build or run the app.
