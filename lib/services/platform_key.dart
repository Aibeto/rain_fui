/// Name of the platform whose shipped FFmpeg build is in use.
///
/// Kept behind a conditional import so the capability layer stays free of
/// Flutter imports and can be exercised by `dart run tool/check_catalog.dart`.
library;

import 'platform_key_stub.dart'
    if (dart.library.io) 'platform_key_io.dart'
    as impl;

/// One of `linux`, `windows`, `macos`, `android`, `web`.
String baselinePlatformKey() => impl.baselinePlatformKey();
