import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'files.dart';
import 'models.dart';
import 'protocol.dart';

enum ReceiveState { waiting, receiving, done, declined, failed, cancelled }

/// One incoming batch of files from one sender.
class ReceiveSession {
  ReceiveSession({
    required this.id,
    required this.sender,
    required this.host,
    required this.files,
  });

  final String id;
  final DeviceInfo sender;
  final String host;
  final List<FileMeta> files;
  final Map<String, int> received = {};
  final Map<String, String> savedPaths = {};
  ReceiveState state = ReceiveState.waiting;

  int get totalBytes => files.fold(0, (a, f) => a + f.size);
  int get receivedBytes => received.values.fold(0, (a, b) => a + b);
  bool get allDone => savedPaths.length == files.length;
}

/// Everything the server needs from the app. Kept as an interface so the
/// server can be tested without Flutter.
abstract class ServerDelegate {
  DeviceInfo get localInfo;

  /// The PIN senders must supply, or null if none is required.
  String? get pin;

  /// Show the request to the user; resolve true to accept.
  Future<bool> approveOffer(ReceiveSession session);

  /// Someone reached us directly. [host] is the address they came from.
  void peerSeen(DeviceInfo info, String host, PeerSource source);

  /// Peers we can vouch for, shared with devices that ask (helps iOS, which
  /// can't read the Tailscale peer list itself, find everyone else).
  List<Map<String, dynamic>> shareablePeers();

  Future<Directory> receiveDirectory();

  void sessionUpdated(ReceiveSession session);
}

class SushiServer {
  SushiServer(this.delegate);

  final ServerDelegate delegate;
  HttpServer? _server;
  final Map<String, ReceiveSession> _sessions = {};

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  /// Binds the first free port starting at [preferredPort].
  Future<int> start({int preferredPort = kDefaultPort, bool loopbackOnly = false}) async {
    if (_server != null) return _server!.port;
    Object? lastError;
    for (var p = preferredPort; p < preferredPort + 10; p++) {
      try {
        _server = loopbackOnly
            ? await HttpServer.bind(InternetAddress.loopbackIPv4, p)
            : await _bindAny(p);
        break;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    final server = _server;
    if (server == null) throw lastError ?? StateError('Could not bind');
    server.idleTimeout = const Duration(seconds: 30);
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<HttpServer> _bindAny(int port) async {
    try {
      return await HttpServer.bind(InternetAddress.anyIPv6, port, v6Only: false);
    } on SocketException {
      return HttpServer.bind(InternetAddress.anyIPv4, port);
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  ReceiveSession? session(String id) => _sessions[id];

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == Api.info) {
        return await _json(req, delegate.localInfo.toJson());
      }
      if (req.method == 'POST' && path == Api.hello) return await _hello(req);
      if (req.method == 'GET' && path == Api.peers) {
        return await _json(req, {'peers': delegate.shareablePeers()});
      }
      if (req.method == 'POST' && path == Api.offer) return await _offer(req);
      if (req.method == 'POST' && path == Api.upload) return await _upload(req);
      if (req.method == 'POST' && path == Api.cancel) return await _cancel(req);
      return await _json(req, {'error': 'not_found'}, status: HttpStatus.notFound);
    } catch (e) {
      try {
        await _json(req, {'error': 'internal'}, status: HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  String _remoteHost(HttpRequest req) =>
      normalizeHost(req.connectionInfo?.remoteAddress.address ?? '');

  Future<Map<String, dynamic>> _readJson(HttpRequest req, {int limit = 1 << 20}) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > limit) throw const FormatException('too large');
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<void> _hello(HttpRequest req) async {
    final body = await _readJson(req);
    final info = DeviceInfo.fromJson(body);
    if (info.id != delegate.localInfo.id) {
      delegate.peerSeen(info, _remoteHost(req), PeerSource.incoming);
    }
    return _json(req, delegate.localInfo.toJson());
  }

  Future<void> _offer(HttpRequest req) async {
    final body = await _readJson(req);
    final sender = DeviceInfo.fromJson(body['sender'] as Map<String, dynamic>);
    final files = [
      for (final f in body['files'] as List) FileMeta.fromJson(f as Map<String, dynamic>)
    ];
    final pin = delegate.pin;
    if (pin != null && body['pin'] != pin) {
      return _json(req, {'error': 'pin'}, status: HttpStatus.unauthorized);
    }
    if (files.isEmpty) {
      return _json(req, {'error': 'empty'}, status: HttpStatus.badRequest);
    }
    final host = _remoteHost(req);
    delegate.peerSeen(sender, host, PeerSource.incoming);
    final session = ReceiveSession(
      id: randomId(),
      sender: sender,
      host: host,
      files: files,
    );
    _sessions[session.id] = session;
    delegate.sessionUpdated(session);

    bool accepted;
    try {
      accepted = await delegate.approveOffer(session).timeout(kOfferTimeout);
    } on TimeoutException {
      accepted = false;
    }
    if (session.state == ReceiveState.cancelled) {
      return _json(req, {'error': 'cancelled'}, status: HttpStatus.gone);
    }
    if (!accepted) {
      session.state = ReceiveState.declined;
      delegate.sessionUpdated(session);
      _sessions.remove(session.id);
      return _json(req, {'error': 'declined'}, status: HttpStatus.forbidden);
    }
    session.state = ReceiveState.receiving;
    delegate.sessionUpdated(session);
    return _json(req, {'session': session.id});
  }

  Future<void> _upload(HttpRequest req) async {
    final session = _sessions[req.uri.queryParameters['session']];
    final fileId = req.uri.queryParameters['file'];
    if (session == null || session.state != ReceiveState.receiving) {
      return _json(req, {'error': 'no_session'}, status: HttpStatus.notFound);
    }
    final meta = session.files.where((f) => f.id == fileId).firstOrNull;
    if (meta == null || session.savedPaths.containsKey(meta.id)) {
      return _json(req, {'error': 'no_file'}, status: HttpStatus.notFound);
    }

    final dir = await delegate.receiveDirectory();
    await dir.create(recursive: true);
    final target = uniquePath(dir, sanitizeFileName(meta.name));
    final part = File('$target.part');
    final sink = part.openWrite();
    var written = 0;
    var lastReport = DateTime.now();
    try {
      await for (final chunk in req) {
        if (session.state == ReceiveState.cancelled) throw const _Cancelled();
        written += chunk.length;
        if (written > meta.size) throw const FormatException('oversize');
        sink.add(chunk);
        session.received[meta.id] = written;
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds > 80) {
          lastReport = now;
          delegate.sessionUpdated(session);
        }
      }
      await sink.flush();
      await sink.close();
      if (written != meta.size) throw const FormatException('short');
      await part.rename(target);
      session.savedPaths[meta.id] = target;
      if (session.allDone) {
        session.state = ReceiveState.done;
        _sessions.remove(session.id);
      }
      delegate.sessionUpdated(session);
      return await _json(req, {'ok': true});
    } catch (e) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete().catchError((_) => part);
      if (session.state != ReceiveState.cancelled) {
        session.state = ReceiveState.failed;
      }
      _sessions.remove(session.id);
      delegate.sessionUpdated(session);
      try {
        await _json(req, {'error': e is _Cancelled ? 'cancelled' : 'failed'},
            status: HttpStatus.badRequest);
      } catch (_) {}
    }
  }

  Future<void> _cancel(HttpRequest req) async {
    final session = _sessions.remove(req.uri.queryParameters['session']);
    if (session != null) {
      session.state = ReceiveState.cancelled;
      delegate.sessionUpdated(session);
    }
    return _json(req, {'ok': true});
  }

  /// Called from the receiving UI to stop an in-progress session.
  void cancelLocally(String sessionId) {
    final s = _sessions.remove(sessionId);
    if (s != null) {
      s.state = ReceiveState.cancelled;
      delegate.sessionUpdated(s);
    }
  }

  Future<void> _json(HttpRequest req, Object body, {int status = HttpStatus.ok}) async {
    final res = req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await res.close();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
