import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import '../protocol.dart';

/// Same-network discovery over UDP multicast. Best effort only: many Wi-Fi
/// networks block it and Tailscale doesn't carry it, which is why the app
/// never depends on it.
class LanDiscovery {
  LanDiscovery({required this.localInfo, required this.onFound});

  final DeviceInfo Function() localInfo;
  final void Function(DeviceInfo info, String host) onFound;

  RawDatagramSocket? _socket;
  final _group = InternetAddress(kMulticastGroup);

  bool get isActive => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    try {
      final reusePort = Platform.isMacOS || Platform.isIOS || Platform.isLinux;
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kMulticastPort,
          reuseAddress: true, reusePort: reusePort);
      s.multicastLoopback = false;
      s.joinMulticast(_group);
      s.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null) return;
        _onPacket(d);
      });
      _socket = s;
    } catch (_) {
      // Multicast unavailable (no entitlement, blocked, etc.). That's fine.
      _socket?.close();
      _socket = null;
    }
  }

  void _onPacket(Datagram d) {
    try {
      final json = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
      if (json['sushi'] != kProtocolVersion) return;
      final info = DeviceInfo.fromJson(json['info'] as Map<String, dynamic>);
      if (info.id == localInfo().id) return;
      onFound(info, normalizeHost(d.address.address));
    } catch (_) {}
  }

  void announce() {
    final s = _socket;
    if (s == null) return;
    final payload = utf8.encode(jsonEncode({'sushi': kProtocolVersion, 'info': localInfo().toJson()}));
    try {
      s.send(payload, _group, kMulticastPort);
    } catch (_) {}
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }
}
