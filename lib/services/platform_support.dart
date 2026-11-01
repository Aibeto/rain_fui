import 'package:flutter/foundation.dart';

/// Whether this build can receive files and folders by dragging them onto the
/// window.
///
/// Only the targets with a pointer and a file-drop channel advertise the
/// affordance. On touch platforms a drop hint would promise something the
/// window cannot do, so every drop mention is gated on this getter.
///
/// Kept free of `dart:io` so the web build evaluates it too.
bool get supportsDropTarget =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS;
