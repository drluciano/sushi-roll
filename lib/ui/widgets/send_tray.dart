import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../core/image_compress.dart';
import '../../core/models.dart';
import '../theme.dart';

/// The bottom area: pick files, see what's picked, get nudged to tap a device.
class SendTray extends StatelessWidget {
  const SendTray({
    super.key,
    required this.picked,
    required this.totalBytes,
    required this.showPhotos,
    required this.onPickFiles,
    required this.onPickPhotos,
    required this.onRemove,
    required this.onClear,
    this.showQuality = false,
    this.quality = ImageQuality.original,
    this.onQualityChanged,
    this.devicesAreBeside = false,
  });

  /// In the side-by-side layout the devices sit next to the tray, not above,
  /// so the "tap a device" hint points sideways.
  final bool devicesAreBeside;

  final List<PickedFile> picked;
  final int totalBytes;
  final bool showPhotos;
  final VoidCallback onPickFiles;
  final VoidCallback onPickPhotos;
  final ValueChanged<PickedFile> onRemove;
  final VoidCallback onClear;

  /// Whether any picked file is a photo, so the quality picker is relevant.
  final bool showQuality;
  final ImageQuality quality;
  final ValueChanged<ImageQuality>? onQualityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? Palette.noriSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.07),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: picked.isEmpty ? _empty(context) : _filled(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('empty'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onPickFiles,
                style: _compact,
                icon: const Icon(Icons.add_rounded),
                label: const _OneLine('Choose files'),
              ),
            ),
            if (showPhotos) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onPickPhotos,
                  style: _compact,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const _OneLine('Photos'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Pick something, then tap a device.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _filled(BuildContext context) {
    final theme = Theme.of(context);
    final count = picked.length;
    return Column(
      key: const ValueKey('filled'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count ${count == 1 ? 'file' : 'files'} ready',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(formatBytes(totalBytes),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                      )),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Add more',
              onPressed: onPickFiles,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Clear',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: picked.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = picked[i];
              return InputChip(
                avatar: Icon(fileIcon(f.name), size: 18),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(f.name, overflow: TextOverflow.ellipsis),
                ),
                onDeleted: () => onRemove(f),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              );
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: showQuality
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _QualityPicker(quality: quality, onChanged: onQualityChanged),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 12),
        Center(child: _TapHint(beside: devicesAreBeside)),
      ],
    );
  }
}

/// Two buttons share a narrow phone width (iPhone Duo's outer screen is
/// about 320pt wide once its camera strip is cleared), so the theme's roomy
/// 22pt side padding would wrap "Choose files" onto two lines.
final ButtonStyle _compact = FilledButton.styleFrom(
  minimumSize: const Size(0, 52),
  padding: const EdgeInsets.symmetric(horizontal: 12),
);

/// A button label that stays on one line and shrinks a little rather than
/// wrapping when space is tight.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

class _TapHint extends StatefulWidget {
  const _TapHint({required this.beside});

  final bool beside;

  @override
  State<_TapHint> createState() => _TapHintState();
}

class _TapHintState extends State<_TapHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final d = 4 * Curves.easeInOut.transform(_c.value);
            final rtl = Directionality.of(context) == TextDirection.rtl;
            return Transform.translate(
              offset: widget.beside ? Offset(rtl ? d : -d, 0) : Offset(0, -d),
              child: child,
            );
          },
          child: Icon(
            widget.beside ? Icons.arrow_back_rounded : Icons.arrow_upward_rounded,
            size: 18,
            color: color,
            textDirection: Directionality.of(context),
          ),
        ),
        const SizedBox(width: 6),
        Text('Now tap a device',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// "Original · High · Medium · Low" for photos, with a one-line hint that
/// says what the choice means.
class _QualityPicker extends StatelessWidget {
  const _QualityPicker({required this.quality, required this.onChanged});

  final ImageQuality quality;
  final ValueChanged<ImageQuality>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.photo_size_select_large_rounded, size: 16, color: muted),
            const SizedBox(width: 6),
            Text('Photo quality',
                style: theme.textTheme.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<ImageQuality>(
          segments: [
            for (final q in ImageQuality.values)
              ButtonSegment(value: q, label: Text(q.label, maxLines: 1, overflow: TextOverflow.fade)),
          ],
          selected: {quality},
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
            textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
          ),
          onSelectionChanged: onChanged == null
              ? null
              : (s) {
                  HapticFeedback.selectionClick();
                  onChanged!(s.first);
                },
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            quality.hint,
            key: ValueKey(quality),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}
