import 'package:flutter/material.dart';

import '../../app/controller.dart';
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
  });

  final List<PickedFile> picked;
  final int totalBytes;
  final bool showPhotos;
  final VoidCallback onPickFiles;
  final VoidCallback onPickPhotos;
  final ValueChanged<PickedFile> onRemove;
  final VoidCallback onClear;

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
                icon: const Icon(Icons.add_rounded),
                label: const Text('Choose files'),
              ),
            ),
            if (showPhotos) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onPickPhotos,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Photos'),
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
        const SizedBox(height: 12),
        const Center(child: _TapHint()),
      ],
    );
  }
}

class _TapHint extends StatefulWidget {
  const _TapHint();

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
          builder: (context, child) => Transform.translate(
            offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)),
            child: child,
          ),
          child: Icon(Icons.arrow_upward_rounded, size: 18, color: color),
        ),
        const SizedBox(width: 6),
        Text('Now tap a device',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
