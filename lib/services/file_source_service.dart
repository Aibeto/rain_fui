import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n.dart';
import '../i18n/i18n_keys.dart';
import '../models/source_selection.dart';
import 'child_listing.dart';
import 'directory_lister.dart';

/// A failure the UI can render: [messageKey] is an i18n key, [detail] is the
/// raw platform error text kept for diagnostics (never the primary message).
class FileSourceException implements Exception {
  const FileSourceException(this.messageKey, {this.detail});

  final String messageKey;
  final String? detail;

  /// Localized message, with the raw detail appended when there is one.
  String localize(BuildContext context) {
    final String message = context.l10n(messageKey);
    final String? extra = detail;
    if (extra == null || extra.trim().isEmpty) {
      return message;
    }
    return '$message\n$extra';
  }

  @override
  String toString() => 'FileSourceException($messageKey, $detail)';
}

/// Bridges the two native entry points (file_picker, desktop_drop) to
/// [SourceSelection]. No media processing happens here — this phase only
/// reports what the user picked.
abstract final class FileSourceService {
  /// Upper bound of child names listed per folder, to keep dialogs usable.
  static const int maxListedChildren = 200;

  /// Native multi-file picker. Returns `null` when the user cancels.
  static Future<SourceSelection?> pickFiles(BuildContext context) async {
    final String dialogTitle = context.l10n(I18nKey.addSourceFiles);
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(dialogTitle: dialogTitle);
    } catch (error) {
      throw FileSourceException(I18nKey.errorPickerFailed, detail: '$error');
    }
    if (picked.isEmpty) {
      return null;
    }
    final List<SelectedFile> files = <SelectedFile>[
      for (final PlatformFile file in picked)
        SelectedFile(name: file.name, path: file.path),
    ];
    return SourceSelection(
      origin: SourceOrigin.filePicker,
      files: files,
      noticeKeys: _pathNotices(files),
    );
  }

  /// Native directory picker. Returns `null` when the user cancels.
  ///
  /// Web has no directory picker (spec §6.1) and Android's document picker can
  /// refuse the request depending on API level, so both are reported as
  /// [FileSourceException]s carrying an i18n key.
  static Future<SourceSelection?> pickFolder(BuildContext context) async {
    if (kIsWeb) {
      throw const FileSourceException(I18nKey.errorFolderUnsupportedWeb);
    }
    final String dialogTitle = context.l10n(I18nKey.addSourceFolder);
    String? path;
    try {
      path = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
    } catch (error) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        throw FileSourceException(
          I18nKey.errorFolderUnsupportedAndroid,
          detail: '$error',
        );
      }
      throw FileSourceException(I18nKey.errorPickerFailed, detail: '$error');
    }
    if (path == null || path.isEmpty) {
      return null;
    }
    final SelectedFolder folder = await folderFromPath(path);
    return SourceSelection(
      origin: SourceOrigin.folderPicker,
      folders: <SelectedFolder>[folder],
    );
  }

  /// Maps a `desktop_drop` payload to a [SourceSelection].
  ///
  /// Returns `null` when the drop carried nothing usable. Every platform quirk
  /// (web paths, macOS file promises, unreadable directories) is contained here
  /// so the widget layer never has to try/catch.
  static Future<SourceSelection?> selectionFromDrop(
    DropDoneDetails details,
  ) async {
    final List<SelectedFile> files = <SelectedFile>[];
    final List<SelectedFolder> folders = <SelectedFolder>[];
    try {
      for (final DropItem item in details.files) {
        if (item is DropItemDirectory) {
          final String path = item.path;
          final String name = item.name.isEmpty ? p.basename(path) : item.name;
          if (kIsWeb || path.isEmpty) {
            folders.add(
              SelectedFolder(
                name: name,
                path: path,
                isWeb: true,
                children: <String>[
                  for (final DropItem child in item.children) child.name,
                ],
              ),
            );
          } else {
            folders.add(await folderFromPath(path));
          }
        } else if (item is DropItemFile) {
          final String path = item.path;
          files.add(
            SelectedFile(
              name: item.name.isEmpty ? p.basename(path) : item.name,
              path: path.isEmpty ? null : path,
            ),
          );
        }
      }
    } catch (error) {
      throw FileSourceException(I18nKey.errorDropFailed, detail: '$error');
    }
    if (files.isEmpty && folders.isEmpty) {
      return null;
    }
    return SourceSelection(
      origin: SourceOrigin.drop,
      files: files,
      folders: folders,
      noticeKeys: _pathNotices(files),
    );
  }

  /// One folder plus its first-level children, or the read error.
  static Future<SelectedFolder> folderFromPath(String path) async {
    final String base = p.basename(path);
    final String name = base.isEmpty ? path : base;
    if (kIsWeb) {
      return SelectedFolder(name: name, path: path, isWeb: true);
    }
    try {
      final ChildListing listing = await listChildNames(
        path,
        limit: maxListedChildren,
      );
      return SelectedFolder(
        name: name,
        path: path,
        children: listing.names,
        truncated: listing.truncated,
      );
    } catch (error) {
      return SelectedFolder(name: name, path: path, errorText: '$error');
    }
  }

  static List<String> _pathNotices(List<SelectedFile> files) {
    if (!kIsWeb || files.isEmpty) {
      return const <String>[];
    }
    final bool anyPath = files.any((SelectedFile file) => file.hasPath);
    return anyPath
        ? const <String>[]
        : const <String>[I18nKey.resultWebPathsUnavailable];
  }
}
