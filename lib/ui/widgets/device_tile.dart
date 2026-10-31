import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../theme.dart';

/// Round gradient badge with the device's platform icon, optionally wrapped
/// in a progress ring.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({
    super.key,
    required this.platform,
    this.size = 60,
    this.progress,
    this.dimmed = false,
  });

  final DevicePlatform platform;
  final double size;
  final double? progress;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = platformGradient(platform);
    final avatar = AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: dimmed ? 0.45 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: dimmed
              ? null
              : [
                  BoxShadow(
                    color: colors.last.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Icon(platformIcon(platform), color: Colors.white, size: size * 0.46),
      ),
    );
    return SizedBox.square(
      dimension: size + 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          avatar,
          if (progress != null)
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 250),
              builder: (context, v, _) => CustomPaint(
                size: Size.square(size + 14),
                painter: _RingPainter(v, Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color);

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(2.5);
    canvas.drawArc(inset, 0, math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = color.withValues(alpha: 0.15));
    canvas.drawArc(inset, -math.pi / 2, math.pi * 2 * value, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

class DeviceTile extends StatefulWidget {
  const DeviceTile({
    super.key,
    required this.name,
    required this.platform,
    required this.subtitle,
    required this.online,
    required this.saved,
    required this.inviting,
    required this.onTap,
    required this.onMore,
    this.progress,
  });

  final String name;
  final DevicePlatform platform;
  final String subtitle;
  final bool online;
  final bool saved;

  /// Files are picked and waiting: the tile gently breathes to say "tap me".
  final bool inviting;
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  State<DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<DeviceTile> with SingleTickerProviderStateMixin {
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _syncBreath();
  }

  @override
  void didUpdateWidget(DeviceTile old) {
    super.didUpdateWidget(old);
    _syncBreath();
  }

  void _syncBreath() {
    if (widget.inviting && widget.online) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highlight = widget.inviting && widget.online;

    return AnimatedBuilder(
      animation: _breath,
      builder: (context, child) {
        final b = Curves.easeInOut.transform(_breath.value);
        return Transform.scale(
          scale: (_pressed ? 0.95 : 1.0) + 0.025 * b,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          widget.onMore();
        },
        onSecondaryTap: widget.onMore,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              width: 2,
              color: highlight ? scheme.primary.withValues(alpha: 0.7) : Colors.transparent,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DeviceAvatar(
                platform: widget.platform,
                dimmed: !widget.online,
                progress: widget.progress,
              ),
              const SizedBox(height: 10),
              Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.online ? Palette.wasabi : theme.disabledColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  if (widget.saved) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.star_rounded, size: 14, color: scheme.primary.withValues(alpha: 0.8)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed "add a device" tile that sits at the end of the grid.
class AddDeviceTile extends StatelessWidget {
  const AddDeviceTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.4);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorder(color),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 74,
                child: Icon(Icons.add_rounded, size: 34, color: color),
              ),
              const SizedBox(height: 10),
              Text('Add device',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('by name or address',
                  style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1), const Radius.circular(24)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
