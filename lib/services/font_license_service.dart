import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;

/// Registers the OFL 1.1 texts of every bundled font with [LicenseRegistry].
///
/// The texts ship as assets (`assets/licenses/`) instead of being inlined so the
/// licenses stay byte-identical to the upstream copies that upstream Google
/// Fonts ships, and so a reviewer can diff them without reading Dart.
abstract final class FontLicenseService {
  /// Asset path → packages the license applies to.
  static const Map<String, List<String>> _licenses = <String, List<String>>{
    'assets/licenses/OFL-SourceSans3.txt': <String>['Source Sans 3'],
    'assets/licenses/OFL-NotoSansSC.txt': <String>['Noto Sans SC'],
    'assets/licenses/OFL-NotoSansTC.txt': <String>['Noto Sans TC'],
    'assets/licenses/OFL-NotoSansJP.txt': <String>['Noto Sans JP'],
    'assets/licenses/OFL-NotoSansKR.txt': <String>['Noto Sans KR'],
    'assets/licenses/OFL-NotoSansArabic.txt': <String>['Noto Sans Arabic'],
    'assets/licenses/OFL-NotoSansThai.txt': <String>['Noto Sans Thai'],
    'assets/licenses/OFL-SourceCodePro.txt': <String>['Source Code Pro'],
  };

  static bool _registered = false;

  /// Idempotent: safe to call from `main()` before `runApp`.
  static void register() {
    if (_registered) {
      return;
    }
    _registered = true;
    for (final MapEntry<String, List<String>> entry in _licenses.entries) {
      LicenseRegistry.addLicense(() async* {
        final String text = await rootBundle.loadString(entry.key);
        yield LicenseEntryWithLineBreaks(entry.value, text);
      });
    }
  }
}
