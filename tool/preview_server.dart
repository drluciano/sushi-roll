// Live UI preview for your phone, served from your PC.
//
//   dart run tool/preview_server.dart                 # follow whatever branch was pushed last
//   dart run tool/preview_server.dart --branch main   # or one branch
//   dart run tool/preview_server.dart --port 8090
//
// Every few seconds it fetches from GitHub. When the branch it follows gets a
// new commit, it builds the web preview (lib/main_preview.dart) and any open
// browser tab reloads itself. Open http://<your-pc's-tailscale-name>:8090 in
// Safari on your iPhone.
//
// It builds in its own checkout under .dart_tool/preview/, so your own working
// copy, branch and uncommitted changes are never touched.
//
// Needs only the Flutter SDK and git on PATH. See docs/PREVIEW.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

late final String repoRoot;
late final String workDir;
late final String srcDir;

String follow = 'auto';
int port = 8090;
Duration interval = const Duration(seconds: 10);

String? builtSha;
String? siteDir;
String state = 'starting'; // starting | building | ready | failed
String label = '';
String message = '';
int version = 0;
bool building = false;

Future<void> main(List<String> args) async {
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--branch':
        follow = args[++i];
      case '--port':
        port = int.parse(args[++i]);
      case '--interval':
        interval = Duration(seconds: int.parse(args[++i]));
      case '-h' || '--help':
        stdout.writeln('Usage: dart run tool/preview_server.dart [--branch auto|<name>] [--port 8090] [--interval 10]');
        return;
      default:
        stderr.writeln('Unknown option ${args[i]}');
        exit(64);
    }
  }

  repoRoot = (await _git(['rev-parse', '--show-toplevel'], dir: Directory.current.path)).trim();
  workDir = _join(repoRoot, '.dart_tool', 'preview');
  srcDir = _join(workDir, 'src');
  await Directory(workDir).create(recursive: true);

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  server.listen(_handle);
  await _printUrls();

  // Check right away, then on a timer. Builds never overlap.
  await _tick();
  Timer.periodic(interval, (_) => _tick());
}

// ------------------------------------------------------------------ building

Future<void> _tick() async {
  if (building) return;
  building = true;
  try {
    await _git(['fetch', '--prune', '--quiet', 'origin']);
    final ref = await _targetRef();
    final sha = (await _git(['rev-parse', ref])).trim();
    if (sha == builtSha) return;
    await _build(ref, sha);
  } catch (e) {
    _log('Check failed: $e');
  } finally {
    building = false;
  }
}

/// The remote branch to build: the named one, or the most recently pushed.
Future<String> _targetRef() async {
  if (follow != 'auto') return 'origin/$follow';
  final out = await _git([
    'for-each-ref',
    '--sort=-committerdate',
    '--format=%(refname:short)',
    'refs/remotes/origin',
  ]);
  return LineSplitter.split(out)
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty && l != 'origin/HEAD' && l != 'origin');
}

Future<void> _build(String ref, String sha) async {
  final short = sha.substring(0, 7);
  final subject = (await _git(['log', '-1', '--format=%s', sha])).trim();
  final branch = ref.replaceFirst('origin/', '');
  label = '$branch @ $short · $subject';
  state = 'building';
  message = '';
  _log('Building $label');

  // A private checkout we can move around freely.
  await _git(['worktree', 'prune']);
  if (!File(_join(srcDir, '.git')).existsSync()) {
    await _git(['worktree', 'add', '--force', '--detach', srcDir, sha]);
  } else {
    await _git(['checkout', '--force', '--quiet', '--detach', sha], dir: srcDir);
    await _git(['clean', '-fdq', '-e', 'build/', '-e', '.dart_tool/', '-e', 'web/icons/', '-e', 'web/favicon.png'],
        dir: srcDir);
  }

  if (!File(_join(srcDir, 'lib', 'main_preview.dart')).existsSync()) {
    _fail('$branch has no lib/main_preview.dart yet, so there is nothing to preview.');
    builtSha = sha;
    return;
  }

  // Icons and favicon aren't committed; flutter create fills in whatever is
  // missing and leaves our index.html and manifest.json alone.
  if (!File(_join(srcDir, 'web', 'icons', 'Icon-192.png')).existsSync()) {
    await _run('flutter', ['create', '--platforms', 'web', '--org', 'com.drluciano', '--project-name', 'sushi_roll', '--no-pub', '.'],
        dir: srcDir);
    final stray = File(_join(srcDir, 'test', 'widget_test.dart'));
    if (stray.existsSync() && stray.readAsStringSync().contains('MyApp')) stray.deleteSync();
  }

  final watch = Stopwatch()..start();
  final result = await _run('flutter', [
    'build',
    'web',
    '-t',
    'lib/main_preview.dart',
    '--no-web-resources-cdn',
    '--dart-define=PREVIEW_LABEL=$label',
  ], dir: srcDir, check: false);
  builtSha = sha;
  if (result.exitCode != 0) {
    final err = '${result.stdout}\n${result.stderr}';
    final lines = LineSplitter.split(err).where((l) => l.contains('Error') || l.contains('error:')).take(6).join('\n');
    _fail(lines.isEmpty ? 'flutter build web failed (exit ${result.exitCode}).' : lines);
    return;
  }

  // Copy the finished build aside, so a page never loads a half-written one.
  final next = _join(workDir, 'site-$short');
  await _copyDir(Directory(_join(srcDir, 'build', 'web')), Directory(next));
  final old = siteDir;
  siteDir = next;
  state = 'ready';
  version++;
  _log('Ready in ${watch.elapsed.inSeconds}s: $label');
  if (old != null && old != next) {
    Timer(const Duration(seconds: 30), () => Directory(old).delete(recursive: true).catchError((_) => Directory(old)));
  }
}

void _fail(String why) {
  state = 'failed';
  message = why;
  version++;
  _log('Build failed:\n$why');
}

// ------------------------------------------------------------------- serving

Future<void> _handle(HttpRequest req) async {
  final res = req.response;
  res.headers.set('Cache-Control', 'no-store');
  try {
    final path = Uri.decodeComponent(req.uri.path);
    if (path == '/__preview/status') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'state': state, 'label': label, 'message': message, 'version': version}));
      return;
    }
    final site = siteDir;
    if (site == null) {
      res.headers.contentType = ContentType.html;
      res.write(_waitingPage());
      return;
    }
    final rel = path == '/' ? 'index.html' : path.substring(1);
    if (rel.split('/').contains('..')) {
      res.statusCode = HttpStatus.forbidden;
      return;
    }
    var file = File(_join(site, rel));
    if (!file.existsSync()) file = File(_join(site, 'index.html'));
    final name = file.path.toLowerCase();
    res.headers.contentType = _contentType(name);
    if (name.endsWith('index.html')) {
      res.write(file.readAsStringSync().replaceFirst('</body>', '${_reloadScript()}</body>'));
    } else {
      await res.addStream(file.openRead());
    }
  } catch (e) {
    res.statusCode = HttpStatus.internalServerError;
    res.write('$e');
  } finally {
    await res.close();
  }
}

ContentType _contentType(String name) {
  if (name.endsWith('.html')) return ContentType.html;
  if (name.endsWith('.js') || name.endsWith('.mjs')) return ContentType('text', 'javascript', charset: 'utf-8');
  if (name.endsWith('.json')) return ContentType.json;
  if (name.endsWith('.wasm')) return ContentType('application', 'wasm');
  if (name.endsWith('.png')) return ContentType('image', 'png');
  if (name.endsWith('.css')) return ContentType('text', 'css', charset: 'utf-8');
  if (name.endsWith('.ttf') || name.endsWith('.otf')) return ContentType('font', 'ttf');
  return ContentType.binary;
}

/// Polls the status endpoint, shows a small banner while a new build is
/// running or if it failed, and reloads the page when a new build is ready.
String _reloadScript() => '''
<script>
(() => {
  const loaded = $version;
  const bar = document.createElement('div');
  bar.style.cssText = 'position:fixed;left:50%;transform:translateX(-50%);top:calc(env(safe-area-inset-top) + 6px);z-index:99999;'
    + 'max-width:92vw;padding:6px 12px;border-radius:999px;font:600 12px -apple-system,system-ui,sans-serif;'
    + 'background:rgba(30,30,30,.88);color:#fff;pointer-events:none;display:none;white-space:pre-wrap;text-align:center';
  document.body.appendChild(bar);
  async function poll() {
    try {
      const s = await (await fetch('/__preview/status', {cache: 'no-store'})).json();
      if (s.state === 'ready' && s.version !== loaded) { location.reload(); return; }
      if (s.state === 'building') { bar.textContent = 'Building ' + s.label + '…'; bar.style.display = 'block'; bar.style.borderRadius = '999px'; }
      else if (s.state === 'failed') { bar.textContent = 'Build failed: ' + s.label + '\\n' + s.message; bar.style.display = 'block'; bar.style.borderRadius = '14px'; }
      else bar.style.display = 'none';
    } catch (_) {}
    setTimeout(poll, 2000);
  }
  poll();
})();
</script>
''';

String _waitingPage() => '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Sushi Roll preview</title>
<style>body{margin:0;height:100vh;display:grid;place-items:center;background:#121614;color:#F3EFE9;
font:16px -apple-system,system-ui,sans-serif;text-align:center}</style></head>
<body><div><div style="font-size:40px">🍣</div><p>First build of the preview is running.<br>This page reloads by itself.</p></div>
${_reloadScript()}</body></html>
''';

// ------------------------------------------------------------------- helpers

Future<String> _git(List<String> args, {String? dir}) async {
  final r = await _run('git', args, dir: dir ?? repoRoot);
  return r.stdout as String;
}

Future<ProcessResult> _run(String exe, List<String> args, {required String dir, bool check = true}) async {
  // runInShell so flutter.bat resolves on Windows.
  final r = await Process.run(exe, args, workingDirectory: dir, runInShell: true);
  if (check && r.exitCode != 0) {
    throw ProcessException(exe, args, '${r.stderr}'.trim(), r.exitCode);
  }
  return r;
}

Future<void> _copyDir(Directory from, Directory to) async {
  if (to.existsSync()) await to.delete(recursive: true);
  await to.create(recursive: true);
  await for (final e in from.list(recursive: true, followLinks: false)) {
    final rel = e.path.substring(from.path.length + 1);
    final target = _join(to.path, rel);
    if (e is Directory) {
      await Directory(target).create(recursive: true);
    } else if (e is File) {
      await File(target).parent.create(recursive: true);
      await e.copy(target);
    }
  }
}

String _join(String a, [String? b, String? c, String? d]) =>
    [a, b, c, d].whereType<String>().join(Platform.pathSeparator);

Future<void> _printUrls() async {
  final urls = <String>['http://localhost:$port'];
  try {
    final ts = await Process.run('tailscale', ['status', '--json'], runInShell: true);
    if (ts.exitCode == 0) {
      final self = (jsonDecode(ts.stdout as String) as Map)['Self'] as Map?;
      final dns = (self?['DNSName'] as String?)?.replaceFirst(RegExp(r'\.$'), '');
      if (dns != null && dns.isNotEmpty) urls.add('http://$dns:$port');
    }
  } catch (_) {}
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      urls.add('http://${a.address}:$port${a.address.startsWith('100.') ? '   (Tailscale)' : ''}');
    }
  }
  stdout.writeln('\nSushi Roll preview, following ${follow == 'auto' ? 'the latest pushed branch' : follow}.');
  stdout.writeln('Open one of these on your phone:');
  for (final u in urls) {
    stdout.writeln('  $u');
  }
  stdout.writeln('');
}

void _log(String s) {
  final t = DateTime.now().toIso8601String().substring(11, 19);
  stdout.writeln('[$t] $s');
}
