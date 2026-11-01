import 'package:flutter/widgets.dart';

import 'app.dart';
import 'src/ffmpeg/android_paths.dart';
import 'src/media/capabilities.dart';
import 'i18n/i18n.dart';
import 'services/font_license_service.dart';
import 'services/encoder_availability.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';

/// Entrypoint.
///
/// Everything the app needs before its first visible frame happens here: font
/// licenses are registered, and the startup locale and theme are resolved from
/// `SharedPreferences` (spec §1). `runApp` is only reached once that work is
/// done, and [StartupActivity] paints nothing, so there is no intermediate UI
/// to flash before the home screen appears.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FontLicenseService.register();

  Locale locale = kFallbackLocale;
  try {
    locale = await LocaleService.loadStartupLocale();
  } catch (error, stackTrace) {
    // A broken preferences store must not block startup: fall back to English.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'rain_fui',
        context: ErrorDescription('while resolving the startup locale'),
      ),
    );
  }

  ThemeMode themeMode = ThemeMode.system;
  try {
    themeMode = await ThemeService.loadStartupMode();
  } catch (error, stackTrace) {
    // Same rule as the locale: a broken store must not block startup.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'rain_fui',
        context: ErrorDescription('while resolving the startup theme'),
      ),
    );
  }

  // Ask the FFmpeg binary in use which encoders it really has. A distribution
  // build brings libx264, libaom or the hardware encoders; the bundled one is
  // native-only. Whatever the answer, the form only offers what can run.
  try {
    final EncoderAvailability availability = await EncoderAvailability.load(
      androidNativeLibraryDir: await AndroidPaths.nativeLibraryDir(),
    );
    if (!availability.probed && availability.error != null) {
      // Not fatal: the fallback list is the shipped build's own, but the log
      // line is the only way to see why a device fell back.
      debugPrint('[rain_fui] encoder probe fell back: ${availability.error}');
    }
    MediaCapabilities.useAvailability(availability);
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'rain_fui',
        context: ErrorDescription('while probing the FFmpeg encoders'),
      ),
    );
  }

  runApp(
    RainFuiApp(
      initialLocale: locale,
      themeService: ThemeService(initial: themeMode),
    ),
  );
}
