import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Two soft colour glows that drift slowly behind everything.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _GlowPainter(_c.value, dark),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.t, this.dark);

  final double t;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final s = size.shortestSide;
    glow(
      Offset(size.width * (0.15 + 0.1 * math.cos(a)), size.height * (0.12 + 0.06 * math.sin(a))),
      s * 0.75,
      Palette.salmon.withValues(alpha: dark ? 0.16 : 0.14),
    );
    glow(
      Offset(size.width * (0.9 + 0.08 * math.sin(a)), size.height * (0.75 + 0.08 * math.cos(a))),
      s * 0.8,
      Palette.wasabi.withValues(alpha: dark ? 0.12 : 0.12),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.t != t || old.dark != dark;
}

/// Gently expanding rings: the "looking for devices" state.
class Radar extends StatefulWidget {
  const Radar({super.key, this.size = 220, required this.child});

  final double size;
  final Widget child;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _RingsPainter(_c.value, color),
          child: child,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final eased = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        center,
        maxR * (0.3 + 0.7 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

/// Fades and lifts its child in the first time it's built.
class EntranceAnimation extends StatelessWidget {
  const EntranceAnimation({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final total = const Duration(milliseconds: 520) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutBack),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - v)),
          child: Transform.scale(scale: 0.92 + 0.08 * v, child: child),
        ),
      ),
      child: child,
    );
  }
}
