import 'dart:io';

/// Desktop and mobile: pick the build that ships with this platform.
String baselinePlatformKey() {
  if (Platform.isAndroid) {
    return 'android';
  }
  if (Platform.isWindows) {
    return 'windows';
  }
  return 'linux';
}
