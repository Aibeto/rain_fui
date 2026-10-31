# rain_fui

A cross-platform FFmpeg GUI built with Flutter. It wraps the `ffmpeg` command
line, so the whole product rests on one integration layer (`lib/src/ffmpeg/`):
find a working FFmpeg for the current platform, run a command, stream its log
and its `-progress` blocks, and hand the exit status back to the caller.

Android, Windows, Linux and the web are supported. iOS and macOS are recognised
but not built: spawning a bundled `ffmpeg` binary is not allowed on iOS, and
this repository does not ship a notarised macOS build.

## Why a subprocess and not libav* FFI

The product *is* a command line wrapper, so the app runs a real `ffmpeg`
executable on every platform instead of linking `libav*`:

- identical behaviour and error messages everywhere, and the full CLI surface,
- the caller gets the exact argv plus parsed `-progress pipe:1` blocks,
- no ABI gymnastics, no per-platform FFI bindings, no glue C code.

Per platform that means:

| Platform | Shipped artifact | How it runs |
| --- | --- | --- |
| Linux | `lib/ffmpeg` in the bundle | `Process.start` on the bundled path |
| Windows | `ffmpeg.exe` next to the runner | `Process.start` on the bundled path |
| Android | `lib/<abi>/libffmpeg_exe.so` in the APK | exec'd from `nativeLibraryDir` |
| Web | `web/ffmpeg/ffmpeg.{js,wasm,worker.js}` | Emscripten (threaded) module in a Web Worker |

Android refuses to exec files from the app's data directory on API 29+, but the
native library directory is executable, hence the `libffmpeg_exe.so` name. The
APK must extract those libs on install, which is why
`android:extractNativeLibs="true"` and `jniLibs { useLegacyPackaging = true }`
are both set.

## FFmpeg

The source lives in `third_party/ffmpeg` as a git submodule pinned to release
**n9.0.2** (`third_party/ffmpeg/RELEASE`). It is built locally, not downloaded
prebuilt: full LTO plus parallel compilation, with the build scripts in
`scripts/ffmpeg/`.

```sh
git submodule update --init --depth 1

# Linux (host build, 20 jobs by default: use --jobs N to change)
scripts/ffmpeg/build-linux.sh
# Android (arm64-v8a by default, see --abis)
scripts/ffmpeg/build-android.sh
# Windows (MSYS2 on Windows, or MinGW-w64 cross-compilation on Linux)
scripts/ffmpeg/build-windows.sh
# Web (needs an activated emsdk with emcc/emar/emnm on PATH)
scripts/ffmpeg/build-web.sh

# Copy the result into the app tree, then build the app
scripts/ffmpeg/install-to-app.sh linux      # or windows, android, web, all
flutter build linux --release
```

Artifacts land in `build/ffmpeg/dist/<target>/` and are reproducible from the
pinned commit. Details, flags and the LTO matrix: [`docs/ffmpeg-build.md`](docs/ffmpeg-build.md).
The interface both sides code against — artifact names, staged paths, wasm ABI —
is [`docs/build-contract.md`](docs/build-contract.md).

### Locating the binary at runtime

`lib/src/ffmpeg/ffmpeg_locator.dart` probes, in order:

1. `RAIN_FUI_FFMPEG_BIN` (then `FFMPEG_BIN`) — absolute path or bare command,
2. the platform bundle location (see the table above),
3. development paths (`linux/ffmpeg/ffmpeg`, `build/ffmpeg/dist/<target>/ffmpeg`),
4. `ffmpeg` on `PATH` (skipped on Android).

Each candidate is verified by running `ffmpeg -version`, so a random executable
named `ffmpeg` is rejected instead of failing later with a cryptic error.

### The web target needs cross-origin isolation

The web build is compiled with pthreads: FFmpeg 9's `ffmpeg` program declares
`threads` as a hard dependency (`configure:4377`) and its scheduler calls
`pthread_create()` for every stage, so a single-threaded wasm build can print
`-version` but cannot transcode. Threads need `SharedArrayBuffer`, and browsers
only expose it to a *cross-origin isolated* document:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

`flutter run -d chrome` does not send those headers, and neither does a plain
`python3 -m http.server`. Use the bundled server instead:

```sh
flutter build web --release
python3 tool/serve_web.py          # http://127.0.0.1:8080, adds COOP/COEP
python3 tool/serve_web.py --no-isolation   # checks the graceful error path
```

Without the headers the app still loads: `createFfmpegBackend()` reports
`unavailableReason` containing "cross-origin isolation" instead of hanging on a
broken wasm module.

## User interface

The current tree is the *UI layer*: a complete shell plus the interaction
skeleton for adding sources. It does not call FFmpeg yet — `lib/src/ffmpeg/` is
in place but nothing in the UI imports it.

- **Components and icons.** [`fluent_ui`](https://pub.dev/packages/fluent_ui)
  everywhere; icon glyphs come only from `fluentui_system_icons`. There is no
  Material icon in the app, and no `Scaffold`: the root layout is a hand-built
  top bar / sidebar / content / bottom bar stack. That is deliberate — Fluent's
  acrylic pane is a backdrop blur, and blur is forbidden here.
- **Startup.** `lib/main.dart` resolves the locale *before* the first frame,
  registers the bundled font licences, and starts an activity that renders
  nothing; its first post-frame callback replaces itself with the home screen,
  so no intermediate frame is ever visible.
- **Locales.** 19 locales, each a plain `Map<String, String>` in `lib/i18n/`
  (`zh_CN.dart`, `en_US.dart`, …). Lookup falls back to `en_US`, then to the key
  itself so a missing string is obvious rather than blank. Persisted choice wins
  over the system locale; an unsupported system locale means `en-US`.
- **Fonts.** Source Sans 3 (Latin, Cyrillic) as the global family, with Noto
  Sans SC/TC/JP/KR, Arabic and Thai as per-script fallbacks, all bundled as
  assets and all OFL. Licence texts are registered through `LicenseRegistry`, so
  they appear in Flutter's licence page.
- **Theme and language.** The top bar cycles light → dark → follow-system
  through a `ValueNotifier<ThemeMode>`; the language button opens a list of the
  19 locales. Choosing one *stores* the choice and returns — the new language
  applies on the next launch, by design.
- **Adding sources.** The bottom bar's "+" offers files (multi-select) or a
  folder; both run the native picker and report the result in one dialog. Files
  show their paths (names plus a note on the web, where paths do not exist);
  folders show the path and their first-level children. Desktop and web also
  accept drag-and-drop onto the content area, with the same result dialog.
- **Platform caveats.** The web has no directory picker and no local paths;
  Android directory selection depends on the document picker, so failures are
  caught and explained instead of crashing. Both cases are covered by their own
  localised message.
- **Android permissions.** `POST_NOTIFICATIONS` and `MANAGE_EXTERNAL_STORAGE`
  are declared, with the runtime request / settings-redirect skeleton in
  `lib/services/android_permission_service.dart`.

Rules the UI code is held to — no blur, no hardcoded user-visible copy outside
the language list, no icons outside `fluentui_system_icons`, and the frozen
service signatures every widget codes against — are written down in
[`docs/ui-contract.md`](docs/ui-contract.md).

## Development

Flutter 3.47 / Dart 3.13, with `fluent_ui`, `file_picker`,
`desktop_drop` and `shared_preferences` as the only application dependencies.

```sh
flutter analyze
flutter test
flutter run -d linux          # needs scripts/ffmpeg/... staged once, see above

# opt-in end-to-end check against a real, freshly built binary
REAL_FFMPEG=build/ffmpeg/dist/linux-x64/ffmpeg \
  flutter test test/real_binary_test.dart
```

Driving FFmpeg from application code:

```dart
import 'src/ffmpeg/ffmpeg.dart';

final backend = createFfmpegBackend(); // io on native, wasm on the web
await backend.initialize();            // probes `ffmpeg -version`
if (!backend.isAvailable) {
  print(backend.unavailableReason);    // e.g. "not built yet: run scripts/ffmpeg/..."
  return;
}

final task = await backend.run(
  FfmpegCommand(['-i', 'input.mp4', '-c:v', 'mpeg4', 'output.mp4']),
);
task.logs.listen(print);
task.progress.listen((p) => print('${p.outTime} @ ${p.speed}x'));
final result = await task.done;        // stdout, stderr, exitCode, wallClock
```

`createFfmpegBackend()` is the only platform-conditional entry point
(`ffmpeg.dart` picks `ffmpeg_io.dart` or `ffmpeg_web.dart`), and every backend
accepts injected dependencies (`FfmpegLocator`, `ProcessStarter`), which is how
the tests run without a real cross-compiled build.

## Licensing

The application is **GPL-3.0-or-later** — see [`LICENSE`](LICENSE). It bundles an
FFmpeg build configured with `--enable-gpl --enable-version3` and *without*
`--enable-nonfree`, which is the most permissive option that is still free
software. That makes the combined work GPLv3.

- [`NOTICE`](NOTICE) — what is bundled and under which terms,
- [`LICENSES/`](LICENSES/) — verbatim FFmpeg licence texts (GPLv2, GPLv3,
  LGPLv2.1, LGPLv3) and notes for redistributors.

If you ship a modified build, keep the corresponding source available (the
submodule commit plus `scripts/ffmpeg/` is exactly that).

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) analyses and tests the
Dart code, then builds the four supported targets, asserts the FFmpeg artifact
actually landed in each bundle, and uploads them. iOS and macOS appear as
explicitly skipped legs — see [`docs/ci.md`](docs/ci.md) for why the requested
`if: !matrix.skip` form cannot work in GitHub Actions and what replaced it.
