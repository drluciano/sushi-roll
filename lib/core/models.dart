import 'dart:math';

enum DevicePlatform { ios, ipados, android, windows, macos, linux, unknown }

DevicePlatform platformFromName(String? name) => DevicePlatform.values
    .firstWhere((p) => p.name == name, orElse: () => DevicePlatform.unknown);

/// What a device says about itself.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.port,
    this.version = 1,
    this.pinRequired = false,
  });

  final String id;
  final String name;
  final DevicePlatform platform;
  final int port;
  final int version;
  final bool pinRequired;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform.name,
        'port': port,
        'version': version,
        'pinRequired': pinRequired,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        id: json['id'] as String,
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : 'Unnamed device',
        platform: platformFromName(json['platform'] as String?),
        port: (json['port'] as num?)?.toInt() ?? 47100,
        version: (json['version'] as num?)?.toInt() ?? 1,
        pinRequired: json['pinRequired'] == true,
      );

  DeviceInfo copyWith({String? name, int? port, bool? pinRequired}) =>
      DeviceInfo(
        id: id,
        name: name ?? this.name,
        platform: platform,
        port: port ?? this.port,
        version: version,
        pinRequired: pinRequired ?? this.pinRequired,
      );
}

/// Where we learned about a peer. Shown as a small badge in the UI.
enum PeerSource { lan, tailscale, saved, incoming }

/// A device we know about, and every address it has answered on.
class Peer {
  Peer(this.info);

  DeviceInfo info;
  final Map<String, DateTime> hosts = {};
  final Set<PeerSource> sources = {};
  bool saved = false;

  DateTime get lastSeen => hosts.values.fold(
      DateTime.fromMillisecondsSinceEpoch(0), (a, b) => b.isAfter(a) ? b : a);

  /// The address that answered most recently.
  String? get bestHost {
    if (hosts.isEmpty) return null;
    final entries = hosts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  /// Hosts ordered best-first, for retrying.
  List<String> get hostsByRecency {
    final entries = hosts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key];
  }

  bool isOnline(DateTime now, Duration staleAfter) =>
      now.difference(lastSeen) < staleAfter;

  void touch(String host, PeerSource source, DateTime when) {
    hosts[host] = when;
    sources.add(source);
  }
}

class FileMeta {
  const FileMeta({required this.id, required this.name, required this.size});

  final String id;
  final String name;
  final int size;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'size': size};

  factory FileMeta.fromJson(Map<String, dynamic> json) => FileMeta(
        id: json['id'] as String,
        name: json['name'] as String,
        size: (json['size'] as num).toInt(),
      );
}

String randomId([int bytes = 12]) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Normalises a remote address string: strips IPv4-mapped IPv6 prefixes and
/// zone ids so the same device doesn't show up under two spellings.
String normalizeHost(String host) {
  var h = host.trim();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.toLowerCase().startsWith('::ffff:') && h.contains('.')) {
    h = h.substring(7);
  }
  final zone = h.indexOf('%');
  if (zone != -1) h = h.substring(0, zone);
  return h;
}
