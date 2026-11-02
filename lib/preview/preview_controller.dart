import 'dart:async';
import 'dart:math';

import '../app/controller.dart';
import '../app/settings.dart';
import '../core/models.dart';
import '../core/protocol.dart';
import '../core/server.dart';

/// An [AppController] with no networking: sample devices, pretend transfers
/// and a pretend incoming request, so the UI can be tried in a browser.
class PreviewController extends AppController {
  PreviewController({super.platform});

  Timer? _keepAlive;
  final _rand = Random();
  final Map<String, String> _routes = {};

  @override
  Future<void> init() async {
    settings = await Settings.load();
    myLanAddress = '192.168.1.42';
    myTailscaleAddresses = ['100.88.12.7'];
    myAddresses = [myLanAddress!, ...myTailscaleAddresses];
    _seed();
    ready = true;
    notifyListeners();
    // Keep the "online" sample devices fresh so they never dim.
    _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) => _touchOnline());
  }

  static const _online = {'zephyrus', 'desktop', 'ipad'};

  void _seed() {
    _add('zephyrus', 'Zephyrus', DevicePlatform.windows, '100.71.3.20', 'Tailscale', saved: true, pin: true);
    _add('desktop', 'DESKTOP-9CMN4QK', DevicePlatform.windows, '192.168.1.20', 'Same Wi-Fi', saved: true);
    _add('ipad', 'Dylan\'s iPad', DevicePlatform.ipados, '100.94.51.8', 'Tailscale');
    _add('office', 'Office PC', DevicePlatform.windows, '100.80.4.2', 'Offline', saved: true, online: false);
  }

  void _add(String id, String name, DevicePlatform platform, String host, String route,
      {bool saved = false, bool pin = false, bool online = true}) {
    final p = Peer(DeviceInfo(id: id, name: name, platform: platform, port: kDefaultPort, pinRequired: pin))
      ..saved = saved;
    if (saved) p.sources.add(PeerSource.saved);
    p.touch(host, PeerSource.tailscale,
        online ? DateTime.now() : DateTime.now().subtract(const Duration(days: 1)));
    _routes[id] = route;
    putPeer(p);
  }

  void _touchOnline() {
    for (final p in peers) {
      if (_online.contains(p.info.id) || _routes[p.info.id] == 'Added') {
        p.touch(p.bestHost ?? '', PeerSource.tailscale, DateTime.now());
      }
    }
    notifyListeners();
  }

  /// Puts the sample devices and transfers back the way they started.
  void reset() {
    for (final p in List.of(peers)) {
      forget(p);
    }
    transfers.clear();
    picked.clear();
    _seed();
    notifyListeners();
  }

  @override
  String describeRoute(Peer p) => isOnline(p) ? (_routes[p.info.id] ?? 'Tailscale') : 'Offline';

  @override
  Future<void> resume() async {}

  @override
  void dispose() {
    _keepAlive?.cancel();
    super.dispose();
  }

  @override
  Future<String> receiveFolderPath() async => 'Files › On My iPhone › Sushi Roll';

  @override
  Future<void> openReceiveFolder() async {}

  @override
  Future<List<PickedFile>> pickFiles({bool media = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final n = _rand.nextInt(900) + 1000;
    if (media) {
      return [
        PickedFile('preview/IMG_$n.HEIC', 'IMG_$n.HEIC', 3400000 + _rand.nextInt(900000)),
        PickedFile('preview/IMG_${n + 1}.HEIC', 'IMG_${n + 1}.HEIC', 2900000 + _rand.nextInt(900000)),
        PickedFile('preview/IMG_${n + 2}.MOV', 'IMG_${n + 2}.MOV', 48000000 + _rand.nextInt(9000000)),
      ];
    }
    return [
      PickedFile('preview/Trip itinerary $n.pdf', 'Trip itinerary.pdf', 840000),
      PickedFile('preview/Screenshot $n.png', 'Screenshot $n.png', 1200000 + _rand.nextInt(400000)),
    ];
  }

  @override
  Future<String?> addByAddress(String input) async {
    final name = input.trim();
    if (name.isEmpty) return 'That doesn\'t look like an address.';
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (name.toLowerCase().contains('fail')) {
      return 'Couldn\'t reach $name. Make sure Sushi Roll is open there and Tailscale is connected.';
    }
    final id = 'added-${_rand.nextInt(1 << 30)}';
    _add(id, name, DevicePlatform.windows, '100.100.${_rand.nextInt(250)}.${_rand.nextInt(250)}', 'Added',
        saved: true);
    return null;
  }

  @override
  Future<void> send(Peer peer, {required Future<String?> Function() askPin}) async {
    if (picked.isEmpty) return;
    final files = List.of(picked);
    picked.clear();
    final t = Transfer(
      id: randomId(),
      direction: TransferDirection.outgoing,
      peerName: peer.info.name,
      peerId: peer.info.id,
      peerPlatform: peer.info.platform,
      fileNames: [for (final f in files) f.name],
      totalBytes: files.fold(0, (a, f) => a + f.size),
    );
    var cancelled = false;
    t.onCancel = () => cancelled = true;
    transfers.insert(0, t);
    notifyListeners();

    if (peer.info.pinRequired && await askPin() == null) cancelled = true;
    // Waiting for the other side to tap Accept.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!cancelled) {
      t.status = TransferStatus.active;
      notifyListeners();
      const steps = 40;
      for (var i = 1; i <= steps && !cancelled; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        t.doneBytes = t.totalBytes * i ~/ steps;
        notifyListeners();
      }
    }
    t.status = cancelled ? TransferStatus.cancelled : TransferStatus.done;
    if (cancelled) t.error = 'Cancelled';
    t.finishedAt = DateTime.now();
    notifyListeners();
  }

  /// Pretends another device just offered some files.
  Future<void> simulateIncoming() async {
    final session = ReceiveSession(
      id: randomId(),
      sender: const DeviceInfo(
          id: 'zephyrus', name: 'Zephyrus', platform: DevicePlatform.windows, port: kDefaultPort),
      host: '100.71.3.20',
      files: const [
        FileMeta(id: 'f0', name: 'Quarterly report.xlsx', size: 512000),
        FileMeta(id: 'f1', name: 'Wallpaper.jpg', size: 4200000),
      ],
    );
    final accepted = await approveOffer(session);
    if (!accepted) {
      session.state = ReceiveState.declined;
      sessionUpdated(session);
      return;
    }
    session.state = ReceiveState.receiving;
    sessionUpdated(session);
    for (final f in session.files) {
      for (var i = 1; i <= 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 70));
        session.received[f.id] = f.size * i ~/ 20;
        sessionUpdated(session);
      }
      session.savedPaths[f.id] = f.name;
    }
    session.state = ReceiveState.done;
    sessionUpdated(session);
  }
}
