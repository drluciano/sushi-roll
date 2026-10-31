import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sushi_roll/ui/adaptive.dart';

DisplayFeature fold(Rect bounds, {bool halfOpen = false}) => DisplayFeature(
      bounds: bounds,
      type: DisplayFeatureType.hinge,
      state: halfOpen ? DisplayFeatureState.postureHalfOpened : DisplayFeatureState.postureFlat,
    );

void main() {
  group('pane layout', () {
    test('phones and the outer display stay single-pane', () {
      expect(computePaneLayout(const Size(393, 852), const []).isSplit, isFalse);
      expect(computePaneLayout(const Size(932, 430), const []).isSplit, isFalse); // phone landscape
      expect(computePaneLayout(const Size(466, 678), const []).isSplit, isFalse); // Duo outer
    });

    test('inner display held upright stacks the panes', () {
      final l = computePaneLayout(const Size(626, 890), const []);
      expect(l.axis, PaneAxis.stacked);
      expect(l.first.bottom, lessThan(445));
      expect(l.second.top, greaterThan(445));
    });

    test('inner display held sideways puts the panes side by side', () {
      final l = computePaneLayout(const Size(890, 626), const []);
      expect(l.axis, PaneAxis.sideBySide);
      expect(l.first.right, lessThan(445));
      expect(l.second.left, greaterThan(445));
    });

    test('a reported horizontal fold (passport / tabletop) splits exactly at it', () {
      final l = computePaneLayout(
        const Size(626, 890),
        [fold(const Rect.fromLTRB(0, 440, 626, 450), halfOpen: true)],
      );
      expect(l.axis, PaneAxis.stacked);
      expect(l.first, const Rect.fromLTRB(0, 0, 626, 440));
      expect(l.second, const Rect.fromLTRB(0, 450, 626, 890));
      expect(l.halfOpen, isTrue);
    });

    test('a reported vertical fold splits side by side', () {
      final l = computePaneLayout(const Size(890, 626), [fold(const Rect.fromLTRB(445, 0, 445, 626))]);
      expect(l.axis, PaneAxis.sideBySide);
      expect(l.first.right, 445);
      expect(l.second.left, 445);
    });

    test('cutouts are not folds', () {
      final cam = DisplayFeature(
        bounds: const Rect.fromLTRB(500, 0, 560, 30),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      expect(computePaneLayout(const Size(393, 852), [cam]).isSplit, isFalse);
    });
  });

  group('synthetic fold', () {
    test('added only when split and nothing is reported', () {
      expect(syntheticFold(const Size(393, 852), const []), isNull);
      final f = syntheticFold(const Size(890, 626), const [])!;
      expect(f.bounds.left, lessThan(445));
      expect(f.bounds.right, greaterThan(445));
      expect(f.bounds.height, 626);
      final real = fold(const Rect.fromLTRB(445, 0, 445, 626));
      expect(syntheticFold(const Size(890, 626), [real]), isNull);
    });
  });

  group('pane insets', () {
    const screen = Size(890, 626);
    const system = EdgeInsets.fromLTRB(0, 24, 44, 20); // status column on the right

    test('only edges touching the screen keep system insets', () {
      final left = paneInsets(const Rect.fromLTRB(0, 0, 433, 626), screen, system, const []);
      expect(left, const EdgeInsets.fromLTRB(0, 24, 0, 20));
      final right = paneInsets(const Rect.fromLTRB(457, 0, 890, 626), screen, system, const []);
      expect(right, const EdgeInsets.fromLTRB(0, 24, 44, 20));
    });

    test('a camera cutout pushes the nearest edge past it', () {
      final cam = DisplayFeature(
        bounds: const Rect.fromLTRB(200, 0, 260, 50),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      final i = paneInsets(const Rect.fromLTRB(0, 0, 433, 626), screen, system, [cam]);
      expect(i.top, 50);
    });
  });
}
