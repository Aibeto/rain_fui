import 'package:flutter/foundation.dart';

import '../i18n/i18n_keys.dart';

/// Where a [SourceSelection] came from. Drives the result dialog title only.
enum SourceOrigin { filePicker, folderPicker, drop }

/// One picked or dropped file.
@immutable
class SelectedFile {
  const SelectedFile({required this.name, this.path});

  /// Base name, always present (web has nothing else).
  final String name;

  /// Absolute path, or `null` when the platform does not expose one (web).
  final String? path;

  bool get hasPath => path != null && path!.isNotEmpty;

  /// What the UI can show without inventing a path.
  String get display => hasPath ? path! : name;

  @override
  String toString() => 'SelectedFile($name, $path)';
}

/// One picked or dropped folder, with its first-level children when readable.
@immutable
class SelectedFolder {
  const SelectedFolder({
    required this.name,
    required this.path,
    this.children = const <String>[],
    this.truncated = false,
    this.isWeb = false,
    this.errorText,
  });

  final String name;
  final String path;

  /// Direct children, already sorted and capped by
  /// `FileSourceService.maxListedChildren`.
  final List<String> children;

  /// True when the folder holds more entries than [children] shows.
  final bool truncated;

  /// True when the platform cannot expose a real filesystem path.
  final bool isWeb;

  /// Raw failure text; when non-null the dialog shows `result_read_error` plus
  /// this detail instead of a child list.
  final String? errorText;

  bool get hasError => errorText != null;

  @override
  String toString() =>
      'SelectedFolder($name, $path, ${children.length} children, error: $errorText)';
}

/// Everything one picker run or one drop produced.
@immutable
class SourceSelection {
  const SourceSelection({
    required this.origin,
    this.files = const <SelectedFile>[],
    this.folders = const <SelectedFolder>[],
    this.noticeKeys = const <String>[],
  });

  final SourceOrigin origin;
  final List<SelectedFile> files;
  final List<SelectedFolder> folders;

  /// i18n keys rendered as small notes under the result list (for example the
  /// "browsers do not expose paths" caveat).
  final List<String> noticeKeys;

  bool get isEmpty => files.isEmpty && folders.isEmpty;

  int get itemCount => files.length + folders.length;

  /// i18n key of the dialog title for this origin.
  String get titleKey => switch (origin) {
    SourceOrigin.filePicker => I18nKey.resultFilesTitle,
    SourceOrigin.folderPicker => I18nKey.resultFolderTitle,
    SourceOrigin.drop => I18nKey.resultDropTitle,
  };

  @override
  String toString() =>
      'SourceSelection($origin, ${files.length} files, ${folders.length} folders)';
}
