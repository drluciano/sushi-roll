import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

class SavedDevice {
  const SavedDevice({required this.host, required this.port, this.info});

  final String host;
  final int port;
  final DeviceInfo? info;

  Map<String, dynamic> toJson() => {'host': host, 'port': port, if (info != null) 'info': info!.toJson()};

  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 47100,
        info: j['info'] is Map<String, dynamic> ? DeviceInfo.fromJson(j['info'] as Map<String, dynamic>) : null,
      );
}

class Settings {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  String get deviceId {
    var id = _prefs.getString('deviceId');
    if (id == null) {
      id = randomId(16);
      _prefs.setString('deviceId', id);
    }
    return id;
  }

  String get deviceName => _prefs.getString('deviceName') ?? _defaultName();
  set deviceName(String v) => _prefs.setString('deviceName', v.trim());

  bool get pinEnabled => _prefs.getBool('pinEnabled') ?? false;
  set pinEnabled(bool v) => _prefs.setBool('pinEnabled', v);

  String get pin {
    var p = _prefs.getString('pin');
    if (p == null) {
      p = (Random.secure().nextInt(9000) + 1000).toString();
      _prefs.setString('pin', p);
    }
    return p;
  }

  void regeneratePin() => _prefs.setString('pin', (Random.secure().nextInt(9000) + 1000).toString());

  String? get receiveDir => _prefs.getString('receiveDir');
  set receiveDir(String? v) =>
      v == null ? _prefs.remove('receiveDir') : _prefs.setString('receiveDir', v);

  List<SavedDevice> get savedDevices {
    final raw = _prefs.getStringList('savedDevices') ?? const [];
    final out = <SavedDevice>[];
    for (final s in raw) {
      try {
        out.add(SavedDevice.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  set savedDevices(List<SavedDevice> list) =>
      _prefs.setStringList('savedDevices', [for (final d in list) jsonEncode(d.toJson())]);

  bool get seenWelcome => _prefs.getBool('seenWelcome') ?? false;
  set seenWelcome(bool v) => _prefs.setBool('seenWelcome', v);

  String _defaultName() {
    String? host;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        host = Platform.localHostname.split('.').first;
      } catch (_) {}
    }
    final name = (host != null && host.isNotEmpty && host != 'localhost') ? host : friendlyName();
    _prefs.setString('deviceName', name);
    return name;
  }
}

const _adjectives = ['Swift', 'Happy', 'Cozy', 'Brave', 'Sunny', 'Calm', 'Lucky', 'Zesty', 'Mellow', 'Bright'];
const _fish = ['Salmon', 'Tuna', 'Eel', 'Shrimp', 'Octopus', 'Scallop', 'Mackerel', 'Yellowtail', 'Squid', 'Urchin'];

String friendlyName() {
  final r = Random();
  return '${_adjectives[r.nextInt(_adjectives.length)]} ${_fish[r.nextInt(_fish.length)]}';
}
