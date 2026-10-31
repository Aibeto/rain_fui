import 'dart:io';

import 'package:path/path.dart' as p;

import 'child_listing.dart';

/// IO implementation: reads one level of [path], sorted by name.
///
/// Throws [FileSystemException] when the directory cannot be read; the caller
/// turns that into a readable message instead of crashing.
Future<ChildListing> listChildNames(String path, {int limit = 200}) async {
  final List<String> names = <String>[];
  bool truncated = false;
  final Directory directory = Directory(path);
  await for (final FileSystemEntity entity in directory.list(
    followLinks: false,
  )) {
    names.add(p.basename(entity.path));
    if (names.length > limit) {
      truncated = true;
      names.removeLast();
      break;
    }
  }
  names.sort(
    (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
  return ChildListing(names: names, truncated: truncated);
}
