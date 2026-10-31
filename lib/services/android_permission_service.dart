import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only permission plumbing shared with `MainActivity.kt`.
///
/// This phase only needs the skeleton required by spec §7 — the manifest
/// declarations plus a basic request path — because the notification feature
/// and the all-files management screen are not built yet. Every entry point is
/// a no-op on web and on non-Android desktop targets so callers never have to
/// branch on the platform themselves.
abstract final class AndroidPermissionService {
  /// Channel name shared with `MainActivity.configureFlutterEngine`.
  static const MethodChannel _channel = MethodChannel('rain_fui/permissions');

  /// Asks for `POST_NOTIFICATIONS` on Android 13 (API 33) and newer.
  ///
  /// Returns `true` when the permission is granted. Below API 33 Android grants
  /// notifications at install time, so the platform answers `true` without a
  /// prompt. A missing or failing channel (desktop, web, platform error) is
  /// reported as `false` instead of throwing.
  static Future<bool> requestNotificationPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return granted ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system screen that manages the all-files access permission.
  ///
  /// The native side falls back to the global
  /// `ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION` screen when the per-app screen
  /// is unavailable. Failures on non-Android targets are swallowed: there is
  /// nothing to open there.
  static Future<void> openManageAllFilesSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openManageAllFilesSettings');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
