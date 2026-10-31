import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// How the screen is divided. On iPhone Duo (and other foldables) the split
/// follows the fold; on large flat screens it follows the longer axis.
enum PaneAxis {
  /// One pane: a regular phone, or iPhone Duo's outer display.
  none,

  /// Two panes side by side, divided by a vertical fold or gutter.
  sideBySide,

  /// Two panes stacked, divided by a horizontal fold or gutter
  /// (iPhone Duo held like a passport or half-open on a table).
  stacked,
}

class PaneLayout {
  const PaneLayout.single(Size size)
      : axis = PaneAxis.none,
        first = Offset.zero & size,
        second = Rect.zero,
        halfOpen = false;

  const PaneLayout({
    required this.axis,
    required this.first,
    required this.second,
    this.halfOpen = false,
  });

  final PaneAxis axis;

  /// Devices live here: the left pane, or the top pane.
  final Rect first;

  /// Sending and transfers live here: the right pane, or the bottom pane.
  final Rect second;

  /// The device is partly folded, so the panes face different directions.
  final bool halfOpen;

  bool get isSplit => axis != PaneAxis.none;

  @override
  bool operator ==(Object other) =>
      other is PaneLayout &&
      other.axis == axis &&
      other.first == first &&
      other.second == second &&
      other.halfOpen == halfOpen;

  @override
  int get hashCode => Object.hash(axis, first, second, halfOpen);

  @override
  String toString() => 'PaneLayout($axis, $first, $second, halfOpen: $halfOpen)';
}

/// Below this, a screen is phone-sized and stays a single pane.
const double kTwoPaneMinShortestSide = 560;
const double kTwoPaneMinLongestSide = 780;

/// Space left on each side of a synthetic split, so nothing sits on the crease.
const double kFoldGutter = 12;

bool isFold(DisplayFeature f) =>
    f.type == DisplayFeatureType.fold || f.type == DisplayFeatureType.hinge;

/// Decides the pane layout from the screen size and the display features
/// Flutter reports (on iPhone Duo these come from the iOS 27.1 hinge and
/// reserved-region APIs via duo_display).
PaneLayout computePaneLayout(Size size, List<DisplayFeature> features) {
  final w = size.width;
  final h = size.height;
  for (final f in features.where(isFold)) {
    final b = f.bounds;
    final halfOpen = f.state == DisplayFeatureState.postureHalfOpened;
    if (b.top <= 1 && b.bottom >= h - 1 && b.left > 0 && b.right < w) {
      // A vertical line from top to bottom: panes side by side.
      return PaneLayout(
        axis: PaneAxis.sideBySide,
        first: Rect.fromLTRB(0, 0, b.left, h),
        second: Rect.fromLTRB(b.right, 0, w, h),
        halfOpen: halfOpen,
      );
    }
    if (b.left <= 1 && b.right >= w - 1 && b.top > 0 && b.bottom < h) {
      // A horizontal line from edge to edge: panes stacked.
      return PaneLayout(
        axis: PaneAxis.stacked,
        first: Rect.fromLTRB(0, 0, w, b.top),
        second: Rect.fromLTRB(0, b.bottom, w, h),
        halfOpen: halfOpen,
      );
    }
  }
  final shortest = math.min(w, h);
  final longest = math.max(w, h);
  if (shortest < kTwoPaneMinShortestSide || longest < kTwoPaneMinLongestSide) {
    return PaneLayout.single(size);
  }
  if (w >= h) {
    final mid = w / 2;
    return PaneLayout(
      axis: PaneAxis.sideBySide,
      first: Rect.fromLTRB(0, 0, mid - kFoldGutter, h),
      second: Rect.fromLTRB(mid + kFoldGutter, 0, w, h),
    );
  }
  final mid = h / 2;
  return PaneLayout(
    axis: PaneAxis.stacked,
    first: Rect.fromLTRB(0, 0, w, mid - kFoldGutter),
    second: Rect.fromLTRB(0, mid + kFoldGutter, w, h),
  );
}

/// The synthetic crease we add when the system reports none (iPhone Duo held
/// flat open, or a large tablet), so Flutter's own dialogs and sheets open on
/// one side instead of straddling the middle.
DisplayFeature? syntheticFold(Size size, List<DisplayFeature> features) {
  if (features.any(isFold)) return null;
  final layout = computePaneLayout(size, features);
  if (!layout.isSplit) return null;
  final bounds = layout.axis == PaneAxis.sideBySide
      ? Rect.fromLTRB(layout.first.right, 0, layout.second.left, size.height)
      : Rect.fromLTRB(0, layout.first.bottom, size.width, layout.second.top);
  return DisplayFeature(
    bounds: bounds,
    type: DisplayFeatureType.fold,
    state: DisplayFeatureState.postureFlat,
  );
}

/// Safe-area padding for a pane: each edge keeps the system inset only if the
/// pane touches that screen edge, and grows to clear any camera cutout that
/// overlaps the pane near an edge.
EdgeInsets paneInsets(Rect pane, Size screen, EdgeInsets system, List<DisplayFeature> features) {
  var left = pane.left <= 0 ? system.left : 0.0;
  var top = pane.top <= 0 ? system.top : 0.0;
  var right = pane.right >= screen.width ? system.right : 0.0;
  var bottom = pane.bottom >= screen.height ? system.bottom : 0.0;
  for (final f in features.where((f) => f.type == DisplayFeatureType.cutout)) {
    final c = f.bounds.intersect(pane);
    if (c.width <= 0 || c.height <= 0) continue;
    // Push the nearest edge past the cutout.
    final dTop = c.top - pane.top;
    final dBottom = pane.bottom - c.bottom;
    final dLeft = c.left - pane.left;
    final dRight = pane.right - c.right;
    final nearest = [dTop, dBottom, dLeft, dRight].reduce(math.min);
    if (nearest == dTop) {
      top = math.max(top, c.bottom - pane.top);
    } else if (nearest == dBottom) {
      bottom = math.max(bottom, pane.bottom - c.top);
    } else if (nearest == dLeft) {
      left = math.max(left, c.right - pane.left);
    } else {
      right = math.max(right, pane.right - c.left);
    }
  }
  return EdgeInsets.fromLTRB(left, top, right, bottom);
}

/// Sits under MaterialApp. Adds a synthetic fold where needed and pads every
/// edge for cutouts, so all screens and sheets avoid the crease and cameras.
class FoldAwareScope extends StatelessWidget {
  const FoldAwareScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final synthetic = syntheticFold(mq.size, mq.displayFeatures);
    if (synthetic == null) return child;
    return MediaQuery(
      data: mq.copyWith(displayFeatures: [...mq.displayFeatures, synthetic]),
      child: child,
    );
  }
}

/// Lays [child] out inside [rect] as if it were its own screen: correct size,
/// per-edge safe areas, and no display features of its own.
class PaneView extends StatelessWidget {
  const PaneView({super.key, required this.rect, required this.screen, required this.child});

  final Rect rect;
  final Size screen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final insets = paneInsets(rect, screen, mq.padding, mq.displayFeatures);
    final view = paneInsets(rect, screen, mq.viewPadding, mq.displayFeatures);
    return Positioned.fromRect(
      rect: rect,
      child: MediaQuery(
        data: mq.copyWith(
          size: rect.size,
          padding: insets,
          viewPadding: view,
          displayFeatures: const [],
        ),
        child: child,
      ),
    );
  }
}
