import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sushi_roll/app/settings.dart';

void main() {
  test('tray settings default to close-to-tray on, minimize-to-tray off', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.load();
    expect(s.closeToTray, isTrue);
    expect(s.minimizeToTray, isFalse);

    s.closeToTray = false;
    s.minimizeToTray = true;
    final again = await Settings.load();
    expect(again.closeToTray, isFalse);
    expect(again.minimizeToTray, isTrue);
  });
}
