import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sushi_roll/app/controller.dart';
import 'package:sushi_roll/core/client.dart';
import 'package:sushi_roll/core/discovery/tailscale.dart';
import 'package:sushi_roll/core/files.dart';
import 'package:sushi_roll/core/models.dart';
import 'package:sushi_roll/core/server.dart';

class FakeDelegate implements ServerDelegate {
  FakeDelegate(this.dir);

  final Directory dir;
  bool accept = true;
  String? requiredPin;
  final seen = <String>[];
  final updates = <ReceiveState>[];
  int port = 0;

  @override
  DeviceInfo get localInfo =>
      DeviceInfo(id: 'receiver', name: 'Desk', platform: DevicePlatform.windows, port: port);

  @override
  String? get pin => requiredPin;

  @override
  Future<bool> approveOffer(ReceiveSession session) async => accept;

  @override
  void peerSeen(DeviceInfo info, String host, PeerSource source) => seen.add('${info.name}@$host');

  @override
  List<Map<String, dynamic>> shareablePeers() => [
        {'host': '100.64.0.9', 'port': 47100},
      ];

  @override
  Future<Directory> receiveDirectory() async => dir;

  @override
  void sessionUpdated(ReceiveSession session) => updates.add(session.state);
}

void main() {
  const me = DeviceInfo(id: 'sender', name: 'Phone', platform: DevicePlatform.ios, port: 1);

  late Directory tmp;
  late FakeDelegate delegate;
  late SushiServer server;
  late SushiClient client;
  late int port;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sushi_test');
    delegate = FakeDelegate(tmp);
    server = SushiServer(delegate);
    port = await server.start(preferredPort: 47300, loopbackOnly: true);
    delegate.port = port;
    client = SushiClient();
  });

  tearDown(() async {
    client.close();
    await server.stop();
    await tmp.delete(recursive: true);
  });

  test('info and hello identify the receiver and register the sender', () async {
    final info = await client.info('127.0.0.1', port);
    expect(info.name, 'Desk');
    final hello = await client.hello('127.0.0.1', port, me);
    expect(hello.id, 'receiver');
    expect(delegate.seen, contains('Phone@127.0.0.1'));
    final peers = await client.peers('127.0.0.1', port);
    expect(peers.single.host, '100.64.0.9');
  });

  test('uploads a file with progress and saves it intact', () async {
    final srcDir = await Directory.systemTemp.createTemp('sushi_src');
    final src = File('${srcDir.path}/photo.jpg');
    final bytes = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    await src.writeAsBytes(bytes);
    final meta = FileMeta(id: 'f0', name: 'photo.jpg', size: bytes.length);

    final session = await client.offer('127.0.0.1', port, me, [meta]);
    var last = 0;
    await client.upload('127.0.0.1', port, session, meta, src, onProgress: (s) => last = s);
    expect(last, bytes.length);

    final saved = File('${tmp.path}${Platform.pathSeparator}photo.jpg');
    expect(await saved.readAsBytes(), bytes);
    expect(delegate.updates.last, ReceiveState.done);
    await srcDir.delete(recursive: true);
  });

  test('declined offers are reported as declined', () async {
    delegate.accept = false;
    await expectLater(
      client.offer('127.0.0.1', port, me, [const FileMeta(id: 'a', name: 'a.txt', size: 1)]),
      throwsA(isA<SushiException>().having((e) => e.code, 'code', 'declined')),
    );
  });

  test('pin is enforced', () async {
    delegate.requiredPin = '1234';
    const files = [FileMeta(id: 'a', name: 'a.txt', size: 1)];
    await expectLater(
      client.offer('127.0.0.1', port, me, files, pin: '0000'),
      throwsA(isA<SushiException>().having((e) => e.code, 'code', 'pin')),
    );
    expect(await client.offer('127.0.0.1', port, me, files, pin: '1234'), isNotEmpty);
  });

  test('unreachable hosts fail fast with a friendly code', () async {
    await expectLater(
      client.info('127.0.0.1', 1, timeout: const Duration(seconds: 2)),
      throwsA(isA<SushiException>().having((e) => e.code, 'code', 'unreachable')),
    );
  });

  group('file names', () {
    test('cannot escape the folder or use reserved names', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'..\..\boot.ini'), 'boot.ini');
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('what?.png'), 'what_.png');
      expect(sanitizeFileName('   '), 'file');
    });

    test('duplicates get numbered', () {
      File('${tmp.path}${Platform.pathSeparator}a.txt').writeAsStringSync('x');
      expect(uniquePath(tmp, 'a.txt'), endsWith('a (1).txt'));
    });
  });

  group('tailscale', () {
    test('recognises tailnet addresses', () {
      expect(Tailscale.isTailscaleAddress('100.101.42.7'), isTrue);
      expect(Tailscale.isTailscaleAddress('100.63.0.1'), isFalse);
      expect(Tailscale.isTailscaleAddress('192.168.1.4'), isFalse);
      expect(Tailscale.isTailscaleAddress('fd7a:115c:a1e0::1'), isTrue);
    });

    test('parses tailscale status --json', () {
      const json = '''
      {"Self": {"HostName": "desk"},
       "Peer": {
         "nodekey:abc": {"HostName": "Dylans-iPhone", "DNSName": "dylans-iphone.tail1234.ts.net.",
                          "TailscaleIPs": ["100.80.1.2", "fd7a:115c:a1e0::2"], "Online": true, "OS": "iOS"},
         "nodekey:def": {"HostName": "old-laptop", "TailscaleIPs": ["100.80.1.3"], "Online": false}
       }}''';
      final peers = Tailscale.parseStatus(json);
      expect(peers, hasLength(2));
      final phone = peers.firstWhere((p) => p.hostName == 'Dylans-iPhone');
      expect(phone.dnsName, 'dylans-iphone.tail1234.ts.net');
      expect(phone.addresses.first, '100.80.1.2');
      expect(phone.online, isTrue);
    });
  });

  test('parses typed addresses', () {
    expect(AppController.parseAddress('my-pc'), ('my-pc', 47100));
    expect(AppController.parseAddress('100.1.2.3:5000'), ('100.1.2.3', 5000));
    expect(AppController.parseAddress('http://desk.tail1.ts.net'), ('desk.tail1.ts.net', 47100));
    expect(AppController.parseAddress('fd7a:115c:a1e0::1'), ('fd7a:115c:a1e0::1', 47100));
    expect(AppController.parseAddress('[fd7a::1]:4000'), ('fd7a::1', 4000));
    expect(AppController.parseAddress('  '), isNull);
  });

  test('normalizes hosts', () {
    expect(normalizeHost('::ffff:192.168.1.5'), '192.168.1.5');
    expect(normalizeHost('fe80::1%en0'), 'fe80::1');
  });

  test('formats sizes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
