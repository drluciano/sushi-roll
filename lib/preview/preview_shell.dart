import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import 'preview_controller.dart';

/// Fake iPhone Duo postures for the web preview. Safari doesn't report the
/// fold, so these add the same display feature the app gets on the device.
enum Posture {
  /// Whatever the browser says (no fold).
  real('No fold', Icons.crop_portrait_rounded),

  /// Open like a book: a vertical fold, panes side by side.
  book('Book', Icons.menu_book_rounded),

  /// Half-open and held like a passport or set on a table: a horizontal
  /// fold, panes stacked, and the "half open" posture.
  passport('Passport', Icons.laptop_chromebook_rounded);

  const Posture(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Thickness of the pretend crease, in logical pixels.
const double _crease = 0;

/// Everything the preview adds on top of the app: the fake fold and a small
/// floating toolbar to change posture, trigger an incoming request and reset.
class PreviewShell extends StatefulWidget {
  const PreviewShell({
    super.key,
    required this.controller,
    required this.child,
    this.buildLabel = '',
  });

  final PreviewController controller;
  final Widget child;

  /// Branch and commit the preview was built from, if known.
  final String buildLabel;

  @override
  State<PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<PreviewShell> {
  Posture _posture = Posture.real;
  bool _open = false;
  Offset? _pos;

  List<DisplayFeature> _features(Size size) {
    switch (_posture) {
      case Posture.real:
        return const [];
      case Posture.book:
        final x = size.width / 2;
        return [
          DisplayFeature(
            bounds: Rect.fromLTRB(x - _crease / 2, 0, x + _crease / 2, size.height),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ];
      case Posture.passport:
        final y = size.height / 2;
        return [
          DisplayFeature(
            bounds: Rect.fromLTRB(0, y - _crease / 2, size.width, y + _crease / 2),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final features = _features(mq.size);
    final pos = _pos ?? Offset(12, mq.padding.top + 76);
    return MediaQuery(
      data: mq.copyWith(displayFeatures: [...mq.displayFeatures, ...features]),
      child: Stack(
        children: [
          widget.child,
          if (_posture != Posture.real) _CreaseLine(posture: _posture),
          Positioned(
            left: pos.dx.clamp(0, mq.size.width - 56),
            top: pos.dy.clamp(0, mq.size.height - 56),
            child: GestureDetector(
              onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
              child: _open ? _panel(context) : _fab(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface.withValues(alpha: 0.85),
      shape: const StadiumBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => _open = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_rounded, size: 16, color: scheme.onInverseSurface),
              const SizedBox(width: 6),
              Text('Preview',
                  style: TextStyle(
                      color: scheme.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onInverseSurface;
    final muted = fg.withValues(alpha: 0.65);
    return Material(
      color: scheme.inverseSurface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(18),
      elevation: 10,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Preview',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _open = false),
                    icon: Icon(Icons.close_rounded, color: fg, size: 18),
                  ),
                ],
              ),
              if (widget.buildLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 8),
                  child: Text(widget.buildLabel, style: TextStyle(color: muted, fontSize: 11)),
                ),
              Text('Fold', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in Posture.values)
                    ChoiceChip(
                      avatar: Icon(p.icon, size: 16),
                      label: Text(p.label),
                      selected: _posture == p,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _posture = p),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _action(Icons.call_received_rounded, 'Incoming request', () {
                setState(() => _open = false);
                widget.controller.simulateIncoming();
              }),
              _action(Icons.restart_alt_rounded, 'Reset sample devices', () {
                widget.controller.reset();
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    final fg = Theme.of(context).colorScheme.onInverseSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// A faint dashed line where the pretend fold is, so it's obvious which
/// posture is on.
class _CreaseLine extends StatelessWidget {
  const _CreaseLine({required this.posture});

  final Posture posture;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _CreasePainter(posture, Theme.of(context).colorScheme.outline)),
      ),
    );
  }
}

class _CreasePainter extends CustomPainter {
  _CreasePainter(this.posture, this.color);

  final Posture posture;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final vertical = posture == Posture.book;
    final length = vertical ? size.height : size.width;
    for (double d = 0; d < length; d += 10) {
      final a = vertical ? Offset(size.width / 2, d) : Offset(d, size.height / 2);
      final b = vertical ? Offset(size.width / 2, d + 5) : Offset(d + 5, size.height / 2);
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(_CreasePainter old) => old.posture != posture || old.color != color;
}
