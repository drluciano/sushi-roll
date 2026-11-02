import 'package:flutter/foundation.dart';

/// Which kind of device the UI is running on.
///
/// Uses Flutter's [defaultTargetPlatform] instead of `dart:io`'s `Platform`,
/// so the same answers come out in the web preview: opened in Safari on an
/// iPhone, the preview lays itself out exactly like the iOS app.
bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

bool get isMobile => isIOS || defaultTargetPlatform == TargetPlatform.android;

/// Has a real file system the user browses (Explorer/Finder) and a
/// choosable receive folder. Never true in the web preview.
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);
