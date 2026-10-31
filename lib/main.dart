import 'package:flutter/widgets.dart';

import 'app.dart';
import 'i18n/i18n.dart';
import 'services/font_license_service.dart';
import 'services/locale_service.dart';

/// Entrypoint.
///
/// Everything the app needs before its first visible frame happens here: font
/// licenses are registered and the startup locale is resolved from
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

  runApp(RainFuiApp(initialLocale: locale));
}
