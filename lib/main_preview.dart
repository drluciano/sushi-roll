import 'package:flutter/material.dart';

import 'app/app.dart';
import 'preview/preview_controller.dart';
import 'preview/preview_shell.dart';

/// Entry point for the web preview: the real UI with sample data and no
/// networking. Build with
///   flutter build web -t lib/main_preview.dart
/// or let tool/preview_server.dart build and serve it.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = PreviewController(platform: detectPlatform());
  controller.init();
  const label = String.fromEnvironment('PREVIEW_LABEL');
  runApp(SushiRollApp(
    controller: controller,
    wrap: (context, child) => PreviewShell(controller: controller, buildLabel: label, child: child!),
  ));
}
