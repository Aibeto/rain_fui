# Rain FUI — UI layer verification

Status of the twelve acceptance points in spec §10, checked statically. This
phase must not build or run the app, so nothing below claims runtime evidence:
the checks are `dart analyze`, two repository scripts, and reading the code
against the spec.

```
$ dart analyze
Analyzing rain_fui...
No issues found!

$ python3 tool/check_i18n.py
… 19 × "42 keys  ok"
i18n_keys.dart 42 constants covered by en_US
All catalogs structurally sound.

$ python3 tool/check_ui_rules.py
No findings: no blur, no Material/Cupertino icons, no stray literals.
```

| # | Acceptance point | Where it is satisfied |
| --- | --- | --- |
| 1 | No visible startup flash, straight to Home | `lib/main.dart` awaits the whole bootstrap before `runApp`; `lib/activities/startup_activity.dart` paints `SizedBox.shrink()` and replaces itself with `HomeActivity` in its first post-frame callback, so the startup route never shows a frame of its own and the back stack stays one entry deep. |
| 2 | Persisted language wins, else supported system locale, else `en-US` | `LocaleService.resolveStartupLocale` (`lib/services/locale_service.dart:37`) tries the stored tag, then `supportedTagForLocale(systemLocale)`, then `kFallbackLocale`. A stored value that is not one of the 19 is treated as absent rather than forcing English. |
| 3 | All copy outside `LanguageActivity` comes from i18n, missing keys fall back to `en-US` | `translate` (`lib/i18n/i18n.dart:203`) is primary map → `en_US` → the key itself. Every widget calls `context.l10n(I18nKey.…)`; `tool/check_ui_rules.py` fails on literal `Text('…')`, `tooltip:`, `label:` and `placeholder:` strings and on empty catalogs, and `tool/check_i18n.py` proves all 19 catalogs carry exactly the frozen 42 keys in the same order. |
| 4 | `LanguageActivity` rows are `code endonym` | `lib/activities/language_activity.dart:11` holds the 19 endonyms; the row renders `'$tag $endonym'` — one space, code first — in a bundled monospace face with the per-script fallback chain. |
| 5 | Theme button cycles light → dark → system | `ThemeService.order` (`lib/services/theme_service.dart:17`) is `[light, dark, system]`; `cycle()` advances modulo the list, `ValueListenableBuilder` feeds `FluentApp.themeMode`, and the top-bar tooltip shows the mode label. |
| 6 | Real bottom bar: left list, centre `+`, right placeholder | `AppBottomBar` (`lib/widgets/bottom_bar.dart:19`) is a full-width 48 px container with three `Expanded` slots; `HomeActivity` places it inside `SafeArea(top: false)` so it sits on the bottom inset, and the root `ColoredBox` extends the bar colour into the inset. |
| 7 | `+` shows a dialog; file and folder pickers are native; one result dialog | `showAddSourceDialog` → `FileSourceService.pickFiles` / `pickFolder` (native `file_picker`) → `showSelectionResultDialog`. Picker failures and the unsupported cases surface through `showMessageDialog`. |
| 8 | Manifest declares `POST_NOTIFICATIONS` and `MANAGE_EXTERNAL_STORAGE` | `android/app/src/main/AndroidManifest.xml:4-5`, with the runtime skeleton in `lib/services/android_permission_service.dart` over the `rain_fui/permissions` channel in `MainActivity.kt`. |
| 9 | Drag and drop of files or folders yields paths/children | `DropSurface` (`lib/widgets/drop_surface.dart:15`) wraps the content region in a `DropTarget`; `FileSourceService.selectionFromDrop` maps `DropItemFile`/`DropItemDirectory` (including web items with no local path) and the result opens the same result dialog. The whole path is wrapped in `try`/`catch`. |
| 10 | No blur anywhere | No `BackdropFilter`, `ImageFilter`, `Acrylic` or `BackdropGroup` in `lib/`, `android/`, `web/`, `windows/`, `linux/` or `macos/` — enforced by `tool/check_ui_rules.py`. The shell is hand-built instead of using Fluent's acrylic pane, and dialogs use the solid barrier colour of `showDialog`. |
| 11 | Icons only from `fluentui_system_icons`, components from `fluent_ui` | Every widget imports `package:fluent_ui/fluent_ui.dart` with `hide FluentIcons` and the icon package separately; `tool/check_ui_rules.py` rejects `Icons.` and `CupertinoIcons`. No Material widget is used — there is not even a `Scaffold`. |
| 12 | All 19 locales render without tofu; fonts OFL, bundled, registered | `pubspec.yaml` bundles Source Sans 3 (Latin + Cyrillic), Noto Sans SC/TC/JP/KR, Noto Sans Arabic, Noto Sans Thai and Source Code Pro; `AppTheme` applies `fontFamilyFallback` per script to all eight `Typography` styles; `FontLicenseService` registers the eight OFL texts from `assets/licenses/` with `LicenseRegistry`. No `google_fonts`, no runtime download. |

## Not covered here

- **Rendering.** Whether the glyphs, the RTL layout or the drag overlay look
  right needs a running app, which spec §0 forbids in this phase.
- **Native pickers.** `file_picker` and `desktop_drop` are exercised only
  through their published APIs; their platform behaviour is untested here.
- **Android permission prompts.** The channel and the manifest lines exist; the
  system dialogs are not exercised.

## Reproducing the checks

```sh
export PATH="$HOME/flutter/bin:$PATH"
dart format --output=none --set-exit-if-changed lib tool
dart analyze
python3 tool/check_i18n.py
python3 tool/check_ui_rules.py          # add --strict to fail on literal copy too
```
