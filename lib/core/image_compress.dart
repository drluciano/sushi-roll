import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// How much to shrink photos before sending. Anything that isn't a still
/// image (videos, documents, GIFs) is always sent untouched.
enum ImageQuality {
  original,
  high,
  medium,
  low;

  String get label => switch (this) {
        original => 'Original',
        high => 'High',
        medium => 'Medium',
        low => 'Low',
      };

  /// One line explaining the choice, shown under the picker.
  String get hint => switch (this) {
        original => 'Photos are sent exactly as they are.',
        high => 'Sharp, about 6 MP. Usually a fraction of the size.',
        medium => 'Great on screens, about 3 MP.',
        low => 'Smallest and quickest, about 1 MP.',
      };

  /// The shorter side of the photo is scaled down to at most this many
  /// pixels (a 4:3 photo at 2160 comes out 2880×2160). Null keeps the
  /// photo as is.
  int? get shortEdge => switch (this) {
        original => null,
        high => 2160,
        medium => 1440,
        low => 960,
      };

  int get jpegQuality => switch (this) {
        original => 100,
        high => 90,
        medium => 80,
        low => 70,
      };

  static ImageQuality fromName(String? name) =>
      ImageQuality.values.where((q) => q.name == name).firstOrNull ?? ImageQuality.original;
}

const _compressible = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'bmp', 'tif', 'tiff'};

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
}

/// Still images we know how to shrink. GIFs are left alone so animations
/// survive, and RAW files are left alone because they're RAW on purpose.
bool isCompressibleImage(String name) => _compressible.contains(_ext(name));

/// PNGs stay PNG (screenshots, transparency); everything else becomes JPEG.
bool _keepsPng(String name) => _ext(name) == 'png';

/// The name the shrunk copy is sent under: "IMG_1234.HEIC" -> "IMG_1234.jpg".
String compressedName(String name) {
  if (_keepsPng(name)) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return '$stem.jpg';
}

/// Size after scaling so the shorter side is at most [shortEdge]. Never
/// scales up.
(int, int) targetSize(int width, int height, int shortEdge) {
  final short = min(width, height);
  if (short <= shortEdge) return (width, height);
  final scale = shortEdge / short;
  return (max(1, (width * scale).round()), max(1, (height * scale).round()));
}

/// Makes a smaller copy of the image at [path] inside [outDir]. Returns the
/// new file, or null when the original should be sent instead: the quality
/// is Original, the file isn't a still image we can read, or shrinking
/// didn't actually make it smaller.
Future<File?> compressImage(String path, String name, ImageQuality quality, Directory outDir) async {
  final edge = quality.shortEdge;
  if (edge == null || !isCompressibleImage(name)) return null;
  final png = _keepsPng(name);
  final out = File('${outDir.path}${Platform.pathSeparator}${compressedName(name)}');
  try {
    await outDir.create(recursive: true);
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      // Native codecs: reads HEIC, honours orientation, keeps the date taken.
      final result = await FlutterImageCompress.compressAndGetFile(
        path,
        out.path,
        minWidth: edge,
        minHeight: edge,
        quality: quality.jpegQuality,
        format: png ? CompressFormat.png : CompressFormat.jpeg,
        keepExif: true,
      );
      if (result == null) return null;
    } else {
      final bytes = await Isolate.run(() => _encodeInDart(path, edge, quality.jpegQuality, png));
      if (bytes == null) return null;
      await out.writeAsBytes(bytes, flush: true);
    }
    if (!await out.exists() || await out.length() >= await File(path).length()) {
      if (await out.exists()) await out.delete();
      return null;
    }
    return out;
  } catch (_) {
    try {
      if (await out.exists()) await out.delete();
    } catch (_) {}
    return null;
  }
}

/// Pure-Dart fallback (Windows). Runs in a background isolate.
Uint8List? _encodeInDart(String path, int shortEdge, int jpegQuality, bool png) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final (w, h) = targetSize(image.width, image.height, shortEdge);
  if (w != image.width || h != image.height) {
    image = img.copyResize(image, width: w, height: h, interpolation: img.Interpolation.average);
  }
  if (png) return img.encodePng(image, level: 6);
  if (image.hasAlpha) {
    // JPEG has no transparency: put see-through parts on white, not black.
    final flat = img.Image(width: image.width, height: image.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    flat.exif = image.exif;
    image = flat;
  }
  return img.encodeJpg(image, quality: jpegQuality, chroma: img.JpegChroma.yuv420);
}
