import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/client.dart';
import '../core/discovery/lan_discovery.dart';
import '../core/discovery/tailscale.dart';
import '../core/models.dart';
import '../core/protocol.dart';
import '../core/server.dart';
import 'settings.dart';

enum TransferDirection { outgoing, incoming }

enum TransferStatus { waiting, active, done, declined, failed, cancelled }

/// One row in the transfers list, either direction.
class Transfer {
  Transfer({
    required this.id,
    required this.direction,
    required this.peerName,
    required this.peerPlatform,
    required this.fileNames,
    required this.totalBytes,
    this.peerId,
  });

  final String id;
  final TransferDirection direction;
  final String peerName;
  final String? peerId;
  final DevicePlatform peerPlatform;
  final List<String> fileNames;
  final int totalBytes;
  int doneBytes = 0;
  TransferStatus status = TransferStatus.waiting;
  String? error;
  List<String> savedPaths = [];
  VoidCallback? onCancel;
  DateTime? finishedAt;

  double get progress => totalBytes == 0 ? 1 : (doneBytes / totalBytes).clamp(0.0, 1.0);
  bool get isFinished =>
      status != TransferStatus.waiting && status != TransferStatus.active;
}

/// A request waiting for the user to tap Accept or Decline.
class IncomingOffer {
  IncomingOffer(this.session);

  final ReceiveSession session;
  final Completer<bool> _answer = Completer<bool>();

  Future<bool> get answered => _answer.future;

  void accept() {
    if (!_answer.isCompleted) _answer.complete(true);
  }

  void decline() {
    if (!_answer.isCompleted) _answer.complete(false);
  }
}

/// Picked file ready to send.
class PickedFile {
  const PickedFile(this.path, this.name, this.size);

  final String path;
  final String name;
  final int size;
}

class AppController extends ChangeNotifier implements ServerDelegate {
  AppController({this.platform = DevicePlatform.unknown});

  final DevicePlatform platform;
  late final Settings settings;
  late final SushiServer _server = SushiServer(this);
  final SushiClient _client = SushiClient();
  late final LanDiscovery _lan = LanDiscovery(localInfo: () => localInfo, onFound: _onLanFound);

  final Map<String, Peer> _peers = {};
  final List<Transfer> transfers = [];
  final List<IncomingOffer> offers = [];
  final List<PickedFile> picked = [];
  final Map<String, Transfer> _incomingBySession = {};
  final Set<String> _probing = {};

  List<String> myAddresses = [];
  List<String> myTailscaleAddresses = [];
  bool tailscaleCliAvailable = false;
  bool ready = false;
  String? startupError;
  int _port = kDefaultPort;
  Timer? _tick;
  int _tickCount = 0;

  final _offerController = StreamController<IncomingOffer>.broadcast();

  /// Fires once per new incoming request so the UI can open a sheet.
  Stream<IncomingOffer> get incomingOffers => _offerController.stream;

  Future<void> init() async {
    settings = await Settings.load();
    try {
      _port = await _server.start();
    } catch (e) {
      startupError = 'Couldn\'t start receiving: $e';
    }
    await _lan.start();
    for (final saved in settings.savedDevices) {
      if (saved.info != null) {
        final p = _peers.putIfAbsent(saved.info!.id, () => Peer(saved.info!));
        p.saved = true;
        p.sources.add(PeerSource.saved);
        p.hosts.putIfAbsent(saved.host, () => DateTime.fromMillisecondsSinceEpoch(0));
      }
    }
    ready = true;
    notifyListeners();
    _refreshAddresses();
    _discover(full: true);
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      _tickCount++;
      _discover(full: _tickCount % 6 == 0);
      notifyListeners(); // lets offline peers dim
    });
  }

  /// Called when the app comes back to the foreground (iOS suspends sockets).
  Future<void> resume() async {
    if (!_server.isRunning) {
      try {
        _port = await _server.start(preferredPort: _port);
        startupError = null;
      } catch (_) {}
    }
    _lan.stop();
    await _lan.start();
    _refreshAddresses();
    _discover(full: true);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lan.stop();
    _server.stop();
    _client.close();
    _offerController.close();
    super.dispose();
  }

  // ---------------------------------------------------------------- identity

  @override
  DeviceInfo get localInfo => DeviceInfo(
        id: settings.deviceId,
        name: settings.deviceName,
        platform: platform,
        port: _port,
        pinRequired: settings.pinEnabled,
      );

  @override
  String? get pin => settings.pinEnabled ? settings.pin : null;

  void rename(String name) {
    if (name.trim().isEmpty) return;
    settings.deviceName = name;
    notifyListeners();
    _discover(full: false);
  }

  void setPinEnabled(bool v) {
    settings.pinEnabled = v;
    notifyListeners();
  }

  void regeneratePin() {
    settings.regeneratePin();
    notifyListeners();
  }

  Future<void> _refreshAddresses() async {
    myAddresses = await Tailscale.localAddressesAll();
    myTailscaleAddresses = myAddresses.where(Tailscale.isTailscaleAddress).toList();
    notifyListeners();
  }

  // ---------------------------------------------------------------- peers

  /// Devices to show: online ones first, then saved-but-offline.
  List<Peer> get peers {
    final now = DateTime.now();
    final list = _peers.values
        .where((p) => p.saved || p.isOnline(now, kPeerStaleAfter))
        .toList();
    list.sort((a, b) {
      final ao = isOnline(a) ? 0 : 1;
      final bo = isOnline(b) ? 0 : 1;
      if (ao != bo) return ao - bo;
      return a.info.name.toLowerCase().compareTo(b.info.name.toLowerCase());
    });
    return list;
  }

  bool isOnline(Peer p) => p.isOnline(DateTime.now(), kPeerStaleAfter);

  /// Short line under a device's name, e.g. "Tailscale" or "Same Wi-Fi".
  String describeRoute(Peer p) {
    if (!isOnline(p)) return 'Offline';
    final host = p.bestHost ?? '';
    if (Tailscale.isTailscaleAddress(host) || host.endsWith('.ts.net')) return 'Tailscale';
    if (p.sources.contains(PeerSource.lan)) return 'Same Wi-Fi';
    return host;
  }

  @override
  void peerSeen(DeviceInfo info, String host, PeerSource source) {
    if (info.id == settings.deviceId || host.isEmpty) return;
    final p = _peers.putIfAbsent(info.id, () => Peer(info));
    p.info = info;
    p.touch(host, source, DateTime.now());
    if (p.saved) _persistSaved();
    notifyListeners();
  }

  void _onLanFound(DeviceInfo info, String host) {
    final known = _peers[info.id];
    peerSeen(info, host, PeerSource.lan);
    // Say hello back so they see us even if their multicast is one-way.
    if (known == null) _probe(host, info.port, PeerSource.lan);
  }

  Future<DeviceInfo?> _probe(String host, int port, PeerSource source) async {
    final key = '$host:$port';
    if (_probing.contains(key)) return null;
    _probing.add(key);
    try {
      final info = await _client.hello(host, port, localInfo);
      if (info.id == settings.deviceId) return null;
      peerSeen(info.copyWith(port: port), host, source);
      return info;
    } catch (_) {
      return null;
    } finally {
      _probing.remove(key);
    }
  }

  Future<void> _discover({required bool full}) async {
    _lan.announce();

    // Saved devices and everyone we've talked to recently.
    final targets = <(String, int, PeerSource)>{};
    for (final s in settings.savedDevices) {
      targets.add((s.host, s.port, PeerSource.saved));
    }
    for (final p in _peers.values) {
      final h = p.bestHost;
      if (h != null && !p.saved) {
        targets.add((h, p.info.port,
            Tailscale.isTailscaleAddress(h) ? PeerSource.tailscale : PeerSource.incoming));
      }
    }

    if (full) {
      final ts = await Tailscale.queryPeers();
      tailscaleCliAvailable = ts != null;
      for (final peer in ts ?? const <TailscalePeer>[]) {
        if (!peer.online) continue;
        final v4 = peer.addresses.where((a) => !a.contains(':')).firstOrNull ??
            peer.addresses.firstOrNull;
        if (v4 != null) targets.add((v4, kDefaultPort, PeerSource.tailscale));
      }
    }

    await Future.wait([for (final t in targets) _probe(t.$1, t.$2, t.$3)]);

    // Ask online peers who they know; this is how iOS learns about the rest
    // of the tailnet, since it can't read the Tailscale peer list itself.
    if (full) {
      final now = DateTime.now();
      final known = {for (final p in _peers.values) ...p.hosts.keys};
      for (final p in _peers.values.where((p) => p.isOnline(now, kPeerStaleAfter)).toList()) {
        final h = p.bestHost;
        if (h == null) continue;
        try {
          final hints = await _client.peers(h, p.info.port);
          await Future.wait([
            for (final hint in hints)
              if (!known.contains(hint.host) && !myAddresses.contains(hint.host))
                _probe(hint.host, hint.port,
                    Tailscale.isTailscaleAddress(hint.host) ? PeerSource.tailscale : PeerSource.incoming),
          ]);
        } catch (_) {}
      }
    }
  }

  @override
  List<Map<String, dynamic>> shareablePeers() {
    final now = DateTime.now();
    return [
      for (final p in _peers.values)
        if (p.isOnline(now, kPeerStaleAfter) && p.bestHost != null)
          {'host': p.bestHost, 'port': p.info.port, 'info': p.info.toJson()},
    ];
  }

  /// Parses "host", "host:port", "[v6]:port", a bare IPv6 address or a URL
  /// into host + port.
  static (String, int)? parseAddress(String input) {
    var s = input.trim().replaceFirst(RegExp(r'^[a-zA-Z]+://'), '').split('/').first;
    if (s.isEmpty) return null;
    if (InternetAddress.tryParse(s)?.type == InternetAddressType.IPv6) {
      return (normalizeHost(s), kDefaultPort);
    }
    final uri = Uri.tryParse('http://$s');
    if (uri == null || uri.host.isEmpty) return null;
    return (normalizeHost(uri.host), uri.hasPort ? uri.port : kDefaultPort);
  }

  /// Manually add a device by name or address. Returns null on success or a
  /// friendly error message.
  Future<String?> addByAddress(String input) async {
    final parsed = parseAddress(input);
    if (parsed == null) return 'That doesn\'t look like an address.';
    final (host, port) = parsed;
    if (myAddresses.contains(host)) return 'That\'s this device.';
    DeviceInfo info;
    try {
      info = await _client.hello(host, port, localInfo, timeout: const Duration(seconds: 5));
    } catch (_) {
      return 'Couldn\'t reach $host. Make sure Sushi Roll is open there and Tailscale is connected.';
    }
    if (info.id == settings.deviceId) return 'That\'s this device.';
    final p = _peers.putIfAbsent(info.id, () => Peer(info));
    p.info = info;
    p.saved = true;
    p.touch(host, PeerSource.saved, DateTime.now());
    _persistSaved();
    notifyListeners();
    return null;
  }

  void toggleSaved(Peer p) {
    p.saved = !p.saved;
    if (p.saved) {
      p.sources.add(PeerSource.saved);
    } else {
      p.sources.remove(PeerSource.saved);
    }
    _persistSaved();
    notifyListeners();
  }

  void forget(Peer p) {
    _peers.remove(p.info.id);
    _persistSaved();
    notifyListeners();
  }

  void _persistSaved() {
    settings.savedDevices = [
      for (final p in _peers.values)
        if (p.saved && p.bestHost != null)
          SavedDevice(host: p.bestHost!, port: p.info.port, info: p.info),
    ];
  }

  // ---------------------------------------------------------------- picking

  void addPicked(Iterable<PickedFile> files) {
    final existing = picked.map((f) => f.path).toSet();
    picked.addAll(files.where((f) => !existing.contains(f.path)));
    notifyListeners();
  }

  void removePicked(PickedFile f) {
    picked.remove(f);
    notifyListeners();
  }

  void clearPicked() {
    picked.clear();
    notifyListeners();
  }

  int get pickedBytes => picked.fold(0, (a, f) => a + f.size);

  // ---------------------------------------------------------------- sending

  Transfer? activeTransferFor(Peer p) => transfers
      .where((t) => t.peerId == p.info.id && !t.isFinished)
      .firstOrNull;

  /// Sends the currently picked files to [peer]. [askPin] is called if the
  /// receiver wants a PIN; return null to give up.
  Future<void> send(Peer peer, {required Future<String?> Function() askPin}) async {
    if (picked.isEmpty) return;
    final files = List.of(picked);
    picked.clear();
    final metas = [
      for (var i = 0; i < files.length; i++)
        FileMeta(id: 'f$i', name: files[i].name, size: files[i].size),
    ];
    final t = Transfer(
      id: randomId(),
      direction: TransferDirection.outgoing,
      peerName: peer.info.name,
      peerId: peer.info.id,
      peerPlatform: peer.info.platform,
      fileNames: [for (final f in files) f.name],
      totalBytes: metas.fold(0, (a, m) => a + m.size),
    );
    final cancel = CancelToken();
    t.onCancel = () {
      cancel.cancel();
      if (t.status == TransferStatus.waiting) {
        // Still waiting on the other side to accept: reflect it right away.
        t.status = TransferStatus.cancelled;
        t.error = 'Cancelled';
        t.finishedAt = DateTime.now();
        notifyListeners();
      }
    };
    transfers.insert(0, t);
    notifyListeners();

    String? host;
    String? session;
    try {
      final opened = await _openSession(peer, metas, askPin);
      host = opened.host;
      session = opened.session;
      if (cancel.isCancelled) throw const SushiException('cancelled');
      t.status = TransferStatus.active;
      notifyListeners();

      var base = 0;
      for (var i = 0; i < files.length; i++) {
        final start = base;
        var lastNotify = DateTime.now();
        await _client.upload(opened.host, peer.info.port, opened.session, metas[i], File(files[i].path),
            cancel: cancel, onProgress: (sent) {
          t.doneBytes = start + sent;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 60) {
            lastNotify = now;
            notifyListeners();
          }
        });
        base += metas[i].size;
        t.doneBytes = base;
        notifyListeners();
      }
      t.status = TransferStatus.done;
    } on SushiException catch (e) {
      t.status = switch (e.code) {
        'declined' => TransferStatus.declined,
        'cancelled' => TransferStatus.cancelled,
        _ => TransferStatus.failed,
      };
      t.error = switch (e.code) {
        'unreachable' => 'Couldn\'t reach ${peer.info.name}',
        'declined' => '${peer.info.name} declined',
        'cancelled' => 'Cancelled',
        _ => 'Something went wrong',
      };
      if (e.code == 'cancelled' && host != null && session != null) {
        _client.cancel(host, peer.info.port, session);
      }
    }
    t.finishedAt = DateTime.now();
    notifyListeners();
  }

  Future<({String host, String session})> _openSession(
      Peer peer, List<FileMeta> metas, Future<String?> Function() askPin) async {
    String? pin;
    for (var attempt = 0;; attempt++) {
      final host = await _reachableHost(peer);
      if (host == null) throw const SushiException('unreachable');
      try {
        final session = await _client.offer(host, peer.info.port, localInfo, metas, pin: pin);
        return (host: host, session: session);
      } on SushiException catch (e) {
        if (e.code != 'pin' || attempt > 3) rethrow;
        pin = await askPin();
        if (pin == null) throw const SushiException('cancelled');
      }
    }
  }

  Future<String?> _reachableHost(Peer peer) async {
    for (final h in peer.hostsByRecency) {
      try {
        await _client.info(h, peer.info.port, timeout: const Duration(seconds: 3));
        peer.touch(h, peer.sources.firstOrNull ?? PeerSource.incoming, DateTime.now());
        return h;
      } catch (_) {}
    }
    return null;
  }

  void dismissTransfer(Transfer t) {
    transfers.remove(t);
    notifyListeners();
  }

  void clearFinished() {
    transfers.removeWhere((t) => t.isFinished);
    notifyListeners();
  }

  // ---------------------------------------------------------------- receiving

  @override
  Future<bool> approveOffer(ReceiveSession session) {
    final offer = IncomingOffer(session);
    offers.add(offer);
    notifyListeners();
    _offerController.add(offer);
    // Give up a little before the sender does, so the sheet closes cleanly.
    Timer(kOfferTimeout - const Duration(seconds: 5), offer.decline);
    return offer._answer.future.whenComplete(() {
      offers.remove(offer);
      notifyListeners();
    });
  }

  @override
  Future<Directory> receiveDirectory() async {
    final custom = settings.receiveDir;
    if (custom != null) return Directory(custom);
    if (Platform.isIOS || Platform.isAndroid) {
      // On iOS this folder shows up in Files → On My iPhone → Sushi Roll.
      return getApplicationDocumentsDirectory();
    }
    final downloads = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    return Directory('${downloads.path}${Platform.pathSeparator}Sushi Roll');
  }

  void setReceiveDir(String? path) {
    settings.receiveDir = path;
    notifyListeners();
  }

  @override
  void sessionUpdated(ReceiveSession s) {
    var t = _incomingBySession[s.id];
    if (t == null) {
      if (s.state == ReceiveState.waiting) return; // shown as an offer, not a transfer yet
      t = Transfer(
        id: s.id,
        direction: TransferDirection.incoming,
        peerName: s.sender.name,
        peerId: s.sender.id,
        peerPlatform: s.sender.platform,
        fileNames: [for (final f in s.files) f.name],
        totalBytes: s.totalBytes,
      )..onCancel = () => _server.cancelLocally(s.id);
      if (s.state == ReceiveState.declined) return;
      _incomingBySession[s.id] = t;
      transfers.insert(0, t);
    }
    t.doneBytes = s.receivedBytes;
    t.savedPaths = s.savedPaths.values.toList();
    t.status = switch (s.state) {
      ReceiveState.waiting => TransferStatus.waiting,
      ReceiveState.receiving => TransferStatus.active,
      ReceiveState.done => TransferStatus.done,
      ReceiveState.declined => TransferStatus.declined,
      ReceiveState.failed => TransferStatus.failed,
      ReceiveState.cancelled => TransferStatus.cancelled,
    };
    if (t.status == TransferStatus.cancelled) t.error = 'Cancelled';
    if (t.status == TransferStatus.failed) t.error = 'Transfer interrupted';
    if (t.isFinished) {
      t.finishedAt = DateTime.now();
      _incomingBySession.remove(s.id);
    }
    notifyListeners();
  }

  /// Opens the receive folder in Explorer/Finder (desktop only).
  Future<void> openReceiveFolder() async {
    final dir = await receiveDirectory();
    await dir.create(recursive: true);
    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir.path]);
    }
  }
}
