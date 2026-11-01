/// Web stub: a browser tab has no output folder.
library;

/// Folder name used on platforms with a filesystem.
const String folderName = 'rain_fui';

/// No filesystem in a browser.
String? defaultPath() => null;

/// Nothing to create in a browser.
Future<String?> ensure() async => null;
