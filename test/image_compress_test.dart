import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sushi_roll/core/image_compress.dart';

/// A noisy photo-like image, so JPEG can't squash it to nothing.
img.Image _photo(int w, int h, {bool alpha = false}) {
  final r = Random(7);
  final im = img.Image(width: w, height: h, numChannels: alpha ? 4 : 3);
  for (final p in im) {
    p
      ..r = (p.x * 255 ~/ w + r.nextInt(40)).clamp(0, 255)
      ..g = (p.y * 255 ~/ h + r.nextInt(40)).clamp(0, 255)
      ..b = r.nextInt(256);
    if (alpha) p.a = p.x < w ~/ 2 ? 0 : 255;
  }
  return im;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sushi_img'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('only still images are compressible', () {
    for (final n in ['a.jpg', 'B.JPEG', 'c.HEIC', 'd.heif', 'e.png', 'f.webp']) {
      expect(isCompressibleImage(n), isTrue, reason: n);
    }
    for (final n in ['a.gif', 'b.mov', 'c.pdf', 'd.dng', 'noext', '.jpg']) {
      expect(isCompressibleImage(n), isFalse, reason: n);
    }
  });

  test('shrunk files become JPEG except PNGs', () {
    expect(compressedName('IMG_1234.HEIC'), 'IMG_1234.jpg');
    expect(compressedName('holiday.photo.jpeg'), 'holiday.photo.jpg');
    expect(compressedName('Screenshot.png'), 'Screenshot.png');
  });

  test('targetSize caps the short edge and never upscales', () {
    expect(targetSize(4032, 3024, 1440), (1920, 1440));
    expect(targetSize(3024, 4032, 1440), (1440, 1920));
    expect(targetSize(800, 600, 1440), (800, 600));
  });

  test('unknown saved quality falls back to Original', () {
    expect(ImageQuality.fromName(null), ImageQuality.original);
    expect(ImageQuality.fromName('nope'), ImageQuality.original);
    expect(ImageQuality.fromName('medium'), ImageQuality.medium);
  });

  test('Original never touches the file', () async {
    final src = File('${tmp.path}/a.jpg')..writeAsBytesSync(img.encodeJpg(_photo(400, 300)));
    expect(await compressImage(src.path, 'a.jpg', ImageQuality.original, tmp), isNull);
  });

  test('Low shrinks a big JPEG', () async {
    final src = File('${tmp.path}/big.jpg')
      ..writeAsBytesSync(img.encodeJpg(_photo(2400, 1800), quality: 95));
    final out = await compressImage(src.path, 'big.jpg', ImageQuality.low, Directory('${tmp.path}/out'));
    expect(out, isNotNull);
    expect(out!.lengthSync(), lessThan(src.lengthSync()));
    final decoded = img.decodeJpg(out.readAsBytesSync())!;
    expect((decoded.width, decoded.height), (1280, 960));
  });

  test('PNG stays PNG and keeps transparency', () async {
    final src = File('${tmp.path}/shot.png')..writeAsBytesSync(img.encodePng(_photo(2000, 1500, alpha: true)));
    final out = await compressImage(src.path, 'shot.png', ImageQuality.low, Directory('${tmp.path}/out'));
    expect(out, isNotNull);
    expect(out!.path, endsWith('shot.png'));
    final decoded = img.decodePng(out.readAsBytesSync())!;
    expect((decoded.width, decoded.height), (1280, 960));
    expect(decoded.getPixel(10, 10).a, 0);
  });

  test('small images that would grow are sent as they are', () async {
    final src = File('${tmp.path}/tiny.jpg')..writeAsBytesSync(img.encodeJpg(_photo(200, 150), quality: 40));
    expect(await compressImage(src.path, 'tiny.jpg', ImageQuality.high, Directory('${tmp.path}/out')), isNull);
  });

  test('unreadable files fall back to the original', () async {
    final src = File('${tmp.path}/fake.jpg')..writeAsStringSync('not an image');
    expect(await compressImage(src.path, 'fake.jpg', ImageQuality.low, Directory('${tmp.path}/out')), isNull);
  });
}
