import 'package:flutter/material.dart';

import '../core/models.dart';

class Palette {
  static const salmon = Color(0xFFFF6F59);
  static const salmonDeep = Color(0xFFF2545B);
  static const wasabi = Color(0xFF7FB77E);
  static const rice = Color(0xFFFBF7F2);
  static const nori = Color(0xFF121614);
  static const noriSurface = Color(0xFF1C2220);
  static const ink = Color(0xFF1F2421);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.salmon,
    brightness: brightness,
  ).copyWith(
    primary: Palette.salmon,
    onPrimary: Colors.white,
    secondary: Palette.wasabi,
    surface: dark ? Palette.noriSurface : Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: dark ? Palette.nori : Palette.rice,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: dark ? const Color(0xFFF3EFE9) : Palette.ink,
      displayColor: dark ? const Color(0xFFF3EFE9) : Palette.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Palette.noriSurface : Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

IconData platformIcon(DevicePlatform p) => switch (p) {
      DevicePlatform.ios => Icons.phone_iphone_rounded,
      DevicePlatform.ipados => Icons.tablet_mac_rounded,
      DevicePlatform.android => Icons.phone_android_rounded,
      DevicePlatform.windows => Icons.desktop_windows_rounded,
      DevicePlatform.macos => Icons.laptop_mac_rounded,
      DevicePlatform.linux => Icons.computer_rounded,
      DevicePlatform.unknown => Icons.devices_other_rounded,
    };

List<Color> platformGradient(DevicePlatform p) => switch (p) {
      DevicePlatform.ios => const [Color(0xFFFF8A65), Color(0xFFFF5E7E)],
      DevicePlatform.ipados => const [Color(0xFFFFB547), Color(0xFFFF7A59)],
      DevicePlatform.windows => const [Color(0xFF5B8CFF), Color(0xFF7A5CFF)],
      DevicePlatform.macos => const [Color(0xFF9AA5B1), Color(0xFF5F6B7A)],
      DevicePlatform.android => const [Color(0xFF7FCB8F), Color(0xFF3FA796)],
      DevicePlatform.linux => const [Color(0xFFFFC857), Color(0xFFE0A100)],
      DevicePlatform.unknown => const [Color(0xFF8FA3A0), Color(0xFF6C807D)],
    };

IconData fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const images = {'jpg', 'jpeg', 'png', 'gif', 'heic', 'heif', 'webp', 'bmp', 'tiff', 'raw', 'dng'};
  const video = {'mov', 'mp4', 'm4v', 'avi', 'mkv', 'webm'};
  const audio = {'mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg'};
  const archives = {'zip', 'rar', '7z', 'tar', 'gz'};
  const docs = {'pdf', 'doc', 'docx', 'txt', 'md', 'pages', 'rtf'};
  if (images.contains(ext)) return Icons.image_rounded;
  if (video.contains(ext)) return Icons.movie_rounded;
  if (audio.contains(ext)) return Icons.music_note_rounded;
  if (archives.contains(ext)) return Icons.folder_zip_rounded;
  if (docs.contains(ext)) return Icons.description_rounded;
  return Icons.insert_drive_file_rounded;
}
