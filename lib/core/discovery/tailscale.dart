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
    // IPv4 by hand, so this also works where dart:io isn't (the web preview).
    final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$').firstMatch(address);
    if (v4 != null) {
      return int.parse(v4[1]!) == 100 && (int.parse(v4[2]!) & 0xC0) == 64;
    }
    final InternetAddress? a;
    try {
      a = InternetAddress.tryParse(address);
    } on UnsupportedError {
      return false;
    }
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

  /// The address another device on the same network would type to reach this
  /// one: a private IPv4 on the Wi-Fi or Ethernet adapter, or null.
  static Future<String?> lanAddress() async {
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      return pickLanAddress([
        for (final i in ifaces)
          for (final a in i.addresses) (i.name, a.address),
      ]);
    } catch (_) {
      return null;
    }
  }

  /// Picks the most likely home-network address from (interface, address)
  /// pairs. Skips Tailscale, cellular and virtual adapters (WSL, Hyper-V,
  /// VirtualBox, VMware, Docker). Exposed for tests.
  static String? pickLanAddress(List<(String, String)> candidates) {
    int? score((String, String) c) {
      final name = c.$1.toLowerCase();
      final a = InternetAddress.tryParse(c.$2);
      if (a == null || a.type != InternetAddressType.IPv4) return null;
      if (isTailscaleAddress(c.$2)) return null;
      const virtual = [
        'pdp_ip', 'utun', 'ipsec', 'bridge', 'awdl', 'llw', 'tailscale',
        'vethernet', 'wsl', 'virtualbox', 'vmware', 'vbox', 'docker', 'hyper-v', 'loopback',
      ];
      if (virtual.any(name.contains)) return null;
      final b = a.rawAddress;
      final int range;
      if (b[0] == 192 && b[1] == 168) {
        range = 30;
      } else if (b[0] == 10) {
        range = 20;
      } else if (b[0] == 172 && b[1] >= 16 && b[1] < 32) {
        range = 10;
      } else {
        return null; // public or link-local: not something to type in
      }
      final preferred = name == 'en0' || name.contains('wi-fi') ||
          name.contains('wlan') || name.contains('wireless') || name.startsWith('ethernet');
      return range + (preferred ? 5 : 0);
    }

    String? best;
    var bestScore = -1;
    for (final c in candidates) {
      final s = score(c);
      if (s != null && s > bestScore) {
        best = c.$2;
        bestScore = s;
      }
    }
    return best;
  }

  /// This device's MagicDNS name from `tailscale status --json`, if any.
  static String? parseSelfDnsName(String json) {
    try {
      final root = jsonDecode(json) as Map<String, dynamic>;
      final self = root['Self'];
      if (self is! Map<String, dynamic>) return null;
      return _trimDot(self['DNSName'] as String?);
    } catch (_) {
      return null;
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
  static Future<({List<TailscalePeer> peers, String? selfDnsName})?> queryStatus() async {
    for (final exe in _cliCandidates()) {
      try {
        final r = await Process.run(exe, ['status', '--json'])
            .timeout(const Duration(seconds: 4));
        if (r.exitCode == 0) {
          final out = r.stdout as String;
          return (peers: parseStatus(out), selfDnsName: parseSelfDnsName(out));
        }
      } catch (_) {
        // try next candidate
      }
    }
    return null;
  }
}
