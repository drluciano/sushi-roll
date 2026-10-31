import 'dart:io';

final _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
const _reservedWindows = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Turns whatever name a sender gave us into something safe to write on any
/// OS. Never lets a name escape the receive folder.
String sanitizeFileName(String raw) {
  var name = raw.split(RegExp(r'[/\\]')).last;
  name = name.replaceAll(_illegal, '_').trim();
  name = name.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (name.isEmpty) name = 'file';
  final stem = name.split('.').first.toUpperCase();
  if (_reservedWindows.contains(stem)) name = '_$name';
  if (name.length > 200) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 16 ? name.substring(dot) : '';
    name = name.substring(0, 200 - ext.length) + ext;
  }
  return name;
}

/// Returns a path in [dir] for [name] that doesn't exist yet,
/// adding " (1)", " (2)"… before the extension when needed.
String uniquePath(Directory dir, String name) {
  final sep = Platform.pathSeparator;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var candidate = '${dir.path}$sep$name';
  var n = 1;
  while (File(candidate).existsSync() || File('$candidate.part').existsSync()) {
    candidate = '${dir.path}$sep$stem ($n)$ext';
    n++;
  }
  return candidate;
}
