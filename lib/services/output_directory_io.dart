/// Filesystem implementation of the output folder.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Folder name created inside Downloads.
const String folderName = 'rain_fui';

/// Downloads directory of the current platform, or null when unknown.
String? _downloadsRoot() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return '/storage/emulated/0/Download';
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      final String? home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null || home.isEmpty) {
        return null;
      }
      return p.join(home, 'Downloads');
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return null;
  }
}

/// Path of the output folder without touching the disk.
String? defaultPath() {
  final String? root = _downloadsRoot();
  return root == null ? null : p.join(root, folderName);
}

/// Creates the output folder and returns its path.
Future<String?> ensure() async {
  final String? path = defaultPath();
  if (path == null) {
    return null;
  }
  try {
    await Directory(path).create(recursive: true);
    return path;
  } on FileSystemException {
    return null;
  }
}
