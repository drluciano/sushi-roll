import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/adaptive.dart';
import '../ui/home_screen.dart';
import '../ui/theme.dart';
import 'controller.dart';

/// The app widget, shared by the real app (lib/main.dart) and the web
/// preview (lib/main_preview.dart). Kept free of iOS-only plugins such as
/// duo_display so the preview can compile for the web.
DevicePlatform detectPlatform() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      return size.shortestSide >= 600 ? DevicePlatform.ipados : DevicePlatform.ios;
    case TargetPlatform.android:
      return DevicePlatform.android;
    case TargetPlatform.windows:
      return DevicePlatform.windows;
    case TargetPlatform.macOS:
      return DevicePlatform.macos;
    case TargetPlatform.linux:
      return DevicePlatform.linux;
    case TargetPlatform.fuchsia:
      return DevicePlatform.unknown;
  }
}

class SushiRollApp extends StatefulWidget {
  const SushiRollApp({super.key, required this.controller, this.wrap});

  final AppController controller;

  /// Wraps everything under MaterialApp. The web preview uses it to fake
  /// iPhone Duo fold postures and to add its toolbar.
  final TransitionBuilder? wrap;

  @override
  State<SushiRollApp> createState() => _SushiRollAppState();
}

class _SushiRollAppState extends State<SushiRollApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.controller.ready) {
      widget.controller.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sushi Roll',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) {
        final scoped = FoldAwareScope(child: child!);
        return widget.wrap?.call(context, scoped) ?? scoped;
      },
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: widget.controller.ready
              ? HomeScreen(controller: widget.controller)
              : const _Splash(),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}
