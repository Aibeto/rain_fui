import 'package:flutter/foundation.dart';

/// Direct children of a folder, already sorted and capped.
@immutable
class ChildListing {
  const ChildListing({
    this.names = const <String>[],
    this.truncated = false,
    this.isSupported = true,
  });

  final List<String> names;

  /// True when the folder holds more entries than [names] shows.
  final bool truncated;

  /// False on platforms where a folder cannot be listed (web).
  final bool isSupported;

  static const ChildListing unsupported = ChildListing(isSupported: false);
}
