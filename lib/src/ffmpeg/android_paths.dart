import 'dart:io';

import 'package:flutter/services.dart';

/// Values that only the Android side can answer.
///
/// `nativeLibraryDir` is where Android extracts (or maps) the `lib*.so` files
/// of the app, and it is the one directory a Flutter app may execute from on
/// Android 10+. There is no `dart:io` API for it, so `MainActivity.kt` exposes
/// it over a [MethodChannel].
abstract final class AndroidPaths {
  static const MethodChannel channel = MethodChannel('rain_fui/ffmpeg');

  static String? _nativeLibraryDir;
  static bool _nativeLibraryDirQueried = false;

  /// Cached `ApplicationInfo.nativeLibraryDir`, or null when unavailable
  /// (not Android, or the channel is missing).
  static Future<String?> nativeLibraryDir() async {
    if (!Platform.isAndroid) return null;
    if (_nativeLibraryDirQueried) return _nativeLibraryDir;
    _nativeLibraryDirQueried = true;
    try {
      final value = await channel.invokeMethod<String>('nativeLibraryDir');
      _nativeLibraryDir = (value == null || value.isEmpty) ? null : value;
    } on PlatformException {
      _nativeLibraryDir = null;
    } on MissingPluginException {
      _nativeLibraryDir = null;
    }
    return _nativeLibraryDir;
  }

  /// The primary ABI of the device, e.g. `arm64-v8a`. Informational only.
  static Future<String?> primaryAbi() async {
    if (!Platform.isAndroid) return null;
    try {
      return await channel.invokeMethod<String>('abi');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Test seam: forget the cached value.
  static void resetCache() {
    _nativeLibraryDir = null;
    _nativeLibraryDirQueried = false;
  }
}
