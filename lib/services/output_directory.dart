/// Default place where finished encodes are written.
///
/// Everything lands in a `rain_fui` folder inside the platform's Downloads
/// directory instead of next to the source file, so the user always knows where
/// to look and the source folder stays untouched.
library;

import 'output_directory_stub.dart'
    if (dart.library.io) 'output_directory_io.dart'
    as impl;

/// Resolves and creates the output directory.
abstract final class OutputDirectory {
  /// Folder name created inside Downloads.
  static const String folderName = impl.folderName;

  /// Path of the output folder, or null where there is no filesystem (web).
  static String? get defaultPath => impl.defaultPath();

  /// Creates the output folder and returns its path.
  ///
  /// Returns null when the platform has no filesystem or the folder cannot be
  /// created; callers then fall back to the source folder.
  static Future<String?> ensure() => impl.ensure();
}
