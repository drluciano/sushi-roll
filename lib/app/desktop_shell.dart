import 'dart:async';
import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'controller.dart';

/// Windows-only window behaviour: the tray icon, hiding to the tray on close
/// or minimize, and starting with Windows. Everything here is a no-op on iOS.
class DesktopShell with TrayListener, WindowListener {
  DesktopShell._();

  static final DesktopShell instance = DesktopShell._();

  /// Passed by the "Start with Windows" entry so the app boots into the tray.
  static const hiddenFlag = '--hidden';

  static bool get supported => Platform.isWindows;

  AppController? _controller;
  StreamSubscription<IncomingOffer>? _offers;
  bool _quitting = false;

  /// Call before `runApp`.
  Future<void> ensureInitialized() async {
    if (!supported) return;
    await windowManager.ensureInitialized();
  }

  /// Call once the controller has loaded its settings.
  Future<void> attach(AppController controller) async {
    if (!supported || _controller != null) return;
    _controller = controller;

    launchAtStartup.setup(
      appName: 'Sushi Roll',
      // Quoted because the install folder ("Program Files") has a space.
      appPath: '"${Platform.resolvedExecutable}"',
      args: const [hiddenFlag],
    );

    windowManager.addListener(this);
    // Always intercept the X button; [onWindowClose] decides what it does.
    await windowManager.setPreventClose(true);

    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('Sushi Roll');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: 'Open Sushi Roll'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));

    // Someone wants to send a file: pop the window up so the accept/decline
    // prompt isn't stuck behind the tray.
    _offers = controller.incomingOffers.listen((_) => show());
  }

  Future<void> show() async {
    if (!supported) return;
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    await _offers?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<bool> launchAtStartupEnabled() async {
    if (!supported || _controller == null) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (_) {
      return false;
    }
  }

  Future<bool> setLaunchAtStartup(bool enabled) async {
    if (!supported || _controller == null) return false;
    try {
      if (enabled) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (_) {}
    return launchAtStartupEnabled();
  }

  // ------------------------------------------------------------ window events

  @override
  void onWindowClose() {
    if (!_quitting && (_controller?.settings.closeToTray ?? false)) {
      windowManager.hide();
    } else {
      quit();
    }
  }

  @override
  void onWindowMinimize() {
    if (_controller?.settings.minimizeToTray ?? false) windowManager.hide();
  }

  // -------------------------------------------------------------- tray events

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() {
    // Without taking focus first, Windows won't close the menu when you click
    // somewhere else. This doesn't unhide the window.
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        show();
      case 'quit':
        quit();
    }
  }
}
