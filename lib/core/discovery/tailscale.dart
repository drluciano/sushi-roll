import 'dart:convert';
import 'dart:io';

class TailscalePeer {
  const TailscalePeer({
    required this.hostName,
    required this.addresses,
    required this.online,
    this.dnsName,
    this.os,
  });

  final String hostName;
  final String? dnsName;
  final List<String> addresses;
  final bool online;
  final String? os;
}

class Tailscale {
  /// True for 100.64.0.0/10 (Tailscale's CGNAT range) and fd7a:115c:a1e0::/48.
  static bool isTailscaleAddress(String address) {
    final a = InternetAddress.tryParse(address);
    if (a == null) return false;
    final b = a.rawAddress;
    if (a.type == InternetAddressType.IPv4) {
      return b[0] == 100 && (b[1] & 0xC0) == 64;
    }
    return b.length == 16 && b[0] == 0xfd && b[1] == 0x7a && b[2] == 0x11 &&
        b[3] == 0x5c && b[4] == 0xa1 && b[5] == 0xe0;
  }

  /// Our own addresses on the tailnet, IPv4 first.
  static Future<List<String>> localAddresses() async {
    final all = await localAddressesAll();
    return all.where(isTailscaleAddress).toList();
  }

  /// Every non-loopback address on this device, IPv4 first.
  static Future<List<String>> localAddressesAll() async {
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.any);
      final out = <String>[
        for (final i in ifaces)
          for (final a in i.addresses)
            if (!a.isLinkLocal) a.address,
      ];
      out.sort((a, b) => (a.contains(':') ? 1 : 0) - (b.contains(':') ? 1 : 0));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Parses `tailscale status --json`. Exposed for tests.
  static List<TailscalePeer> parseStatus(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final peers = (root['Peer'] as Map<String, dynamic>?) ?? const {};
    return [
      for (final p in peers.values.whereType<Map<String, dynamic>>())
        TailscalePeer(
          hostName: (p['HostName'] as String?) ?? '',
          dnsName: _trimDot(p['DNSName'] as String?),
          addresses: [for (final ip in (p['TailscaleIPs'] as List? ?? const [])) ip.toString()],
          online: p['Online'] == true,
          os: p['OS'] as String?,
        ),
    ];
  }

  static String? _trimDot(String? s) =>
      s == null || s.isEmpty ? null : (s.endsWith('.') ? s.substring(0, s.length - 1) : s);

  static List<String> _cliCandidates() {
    if (Platform.isWindows) {
      final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      return ['tailscale', '$pf\\Tailscale\\tailscale.exe'];
    }
    if (Platform.isMacOS) {
      return ['tailscale', '/Applications/Tailscale.app/Contents/MacOS/Tailscale'];
    }
    if (Platform.isLinux) return ['tailscale'];
    return const [];
  }

  /// Asks the local Tailscale client for its peers. Returns null where that's
  /// not possible (iOS can't run the CLI; peers find iOS through hello instead).
  static Future<List<TailscalePeer>?> queryPeers() async {
    for (final exe in _cliCandidates()) {
      try {
        final r = await Process.run(exe, ['status', '--json'])
            .timeout(const Duration(seconds: 4));
        if (r.exitCode == 0) return parseStatus(r.stdout as String);
      } catch (_) {
        // try next candidate
      }
    }
    return null;
  }
}
