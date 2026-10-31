import 'child_listing.dart';
import 'directory_lister_stub.dart'
    if (dart.library.io) 'directory_lister_io.dart'
    as impl;

/// Lists the direct children of a directory without pulling `dart:io` into the
/// web build. On web this returns [ChildListing.unsupported].
Future<ChildListing> listChildNames(String path, {int limit = 200}) =>
    impl.listChildNames(path, limit: limit);
