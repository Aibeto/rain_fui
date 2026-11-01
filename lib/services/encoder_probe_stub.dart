/// Web fallback: a wasm build cannot spawn a second binary, so the shipped
/// encoder list is taken as the truth.
library;

import 'encoder_availability.dart';

Future<EncoderAvailability> probeEncoderAvailability({
  String? androidNativeLibraryDir,
}) async => EncoderAvailability.baseline;
