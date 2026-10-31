import 'child_listing.dart';

/// Web has no filesystem access, so a folder can never be listed there.
Future<ChildListing> listChildNames(String path, {int limit = 200}) async =>
    ChildListing.unsupported;
