import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'protocol.dart';

class SushiException implements Exception {
  const SushiException(this.code, [this.message]);

  /// One of: unreachable, declined, pin, busy, cancelled, failed.
  final String code;
  final String? message;

  @override
  String toString() => 'SushiException($code${message == null ? '' : ': $message'})';
}

/// Lets the UI stop an upload midway.
class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() listener) => _listeners.add(listener);
}

class SushiClient {
  SushiClient() {
    _http.connectionTimeout = const Duration(seconds: 4);
    _http.idleTimeout = const Duration(seconds: 15);
  }

  final HttpClient _http = HttpClient();

  Uri _uri(String host, int port, String path, [Map<String, String>? query]) =>
      Uri(scheme: 'http', host: host, port: port, path: path, queryParameters: query);

  Future<(int, Map<String, dynamic>)> _send(
    String method,
    Uri uri, {
    Object? body,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final req = await _http.openUrl(method, uri).timeout(timeout);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      return (res.statusCode, json);
    } on TimeoutException {
      throw const SushiException('unreachable', 'timed out');
    } on SocketException catch (e) {
      throw SushiException('unreachable', e.message);
    } on HttpException catch (e) {
      throw SushiException('unreachable', e.message);
    } on FormatException {
      throw const SushiException('unreachable', 'not a Sushi Roll device');
    }
  }

  Future<DeviceInfo> info(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    final (status, json) = await _send('GET', _uri(host, port, Api.info), timeout: timeout);
    if (status != 200) throw const SushiException('unreachable');
    return DeviceInfo.fromJson(json);
  }

  /// Tells [host] about us and returns who answered.
  Future<DeviceInfo> hello(String host, int port, DeviceInfo me,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final (status, json) =
        await _send('POST', _uri(host, port, Api.hello), body: me.toJson(), timeout: timeout);
    if (status != 200) throw const SushiException('unreachable');
    return DeviceInfo.fromJson(json);
  }

  /// Hosts the other device knows about: `[{host, port, info}]`.
  Future<List<({String host, int port})>> peers(String host, int port) async {
    final (status, json) = await _send('GET', _uri(host, port, Api.peers));
    if (status != 200) return const [];
    return [
      for (final p in (json['peers'] as List? ?? const []))
        if (p is Map && p['host'] is String)
          (host: p['host'] as String, port: (p['port'] as num?)?.toInt() ?? kDefaultPort),
    ];
  }

  /// Asks the receiver to accept. Resolves with a session id once they tap
  /// Accept; throws [SushiException] with `declined` or `pin` otherwise.
  Future<String> offer(String host, int port, DeviceInfo me, List<FileMeta> files,
      {String? pin}) async {
    final (status, json) = await _send(
      'POST',
      _uri(host, port, Api.offer),
      body: {
        'sender': me.toJson(),
        'files': [for (final f in files) f.toJson()],
        if (pin != null) 'pin': pin,
      },
      timeout: kOfferTimeout + const Duration(seconds: 10),
    );
    if (status == 200) return json['session'] as String;
    if (status == 401) throw const SushiException('pin');
    if (status == 403) throw const SushiException('declined');
    if (status == 410) throw const SushiException('cancelled');
    throw SushiException('failed', json['error']?.toString());
  }

  Future<void> upload(
    String host,
    int port,
    String session,
    FileMeta meta,
    File file, {
    void Function(int sent)? onProgress,
    CancelToken? cancel,
  }) async {
    HttpClientRequest? req;
    cancel?.onCancel(() => req?.abort());
    try {
      req = await _http.openUrl(
          'POST', _uri(host, port, Api.upload, {'session': session, 'file': meta.id}));
      req.contentLength = meta.size;
      req.headers.contentType = ContentType.binary;
      var sent = 0;
      await req.addStream(file.openRead().map((chunk) {
        if (cancel?.isCancelled == true) throw const SushiException('cancelled');
        sent += chunk.length;
        onProgress?.call(sent);
        return chunk;
      }));
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode != 200) throw const SushiException('failed');
    } on SushiException {
      rethrow;
    } catch (e) {
      if (cancel?.isCancelled == true) throw const SushiException('cancelled');
      throw SushiException('failed', e.toString());
    }
  }

  Future<void> cancel(String host, int port, String session) async {
    try {
      await _send('POST', _uri(host, port, Api.cancel, {'session': session}),
          timeout: const Duration(seconds: 2));
    } catch (_) {}
  }

  void close() => _http.close(force: true);
}
