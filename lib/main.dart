import 'package:duo_display/duo_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  final controller = AppController(platform: detectPlatform());
  controller.init();
  // DuoDisplayFeatures reports iPhone Duo's fold and cameras (iOS 27.1 hinge
  // and reserved-region APIs) through MediaQuery.displayFeatures. Elsewhere
  // it does nothing.
  runApp(DuoDisplayFeatures(child: SushiRollApp(controller: controller)));
}

