import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/utils/viewport_visibility.dart';

const Key _targetKey = ValueKey<String>('target');

/// A 100x50 target centred in the view, with [cover] stacked above it.
Widget _screen({Widget? cover, Widget? targetChild}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          Center(
            child: SizedBox(
              key: _targetKey,
              width: 100,
              height: 50,
              child: targetChild,
            ),
          ),
          if (cover != null) cover,
        ],
      ),
    ),
  );
}

Widget _opaque({Widget? child}) {
  return Listener(
    behavior: HitTestBehavior.opaque,
    child: child ?? const SizedBox(width: 100, height: 50),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isRectOutsideViewport()', () {
    const Size viewport = Size(800, 600);

    test('is false for a rect fully inside the viewport', () {
      expect(
        isRectOutsideViewport(const Rect.fromLTWH(10, 10, 100, 50), viewport),
        isFalse,
      );
    });

    test('is false for a rect that only partly overlaps an edge', () {
      expect(
        isRectOutsideViewport(
            const Rect.fromLTWH(750, 550, 100, 100), viewport),
        isFalse,
      );
    });

    test('is true for a rect beyond any edge of the viewport', () {
      expect(
        isRectOutsideViewport(const Rect.fromLTWH(0, 900, 100, 50), viewport),
        isTrue,
      );
      expect(
        isRectOutsideViewport(const Rect.fromLTWH(-200, 0, 100, 50), viewport),
        isTrue,
      );
    });

    test('is true for a rect that only touches the viewport edge', () {
      expect(
        isRectOutsideViewport(const Rect.fromLTWH(800, 0, 100, 50), viewport),
        isTrue,
      );
    });

    test('is false for a rect with no area, which carries no position', () {
      expect(isRectOutsideViewport(Rect.zero, viewport), isFalse);
    });
  });

  group('probeHitAt()', () {
    HitProbe probeTarget(WidgetTester tester, {Offset? point}) {
      return probeHitAt(
        target: tester.renderObject(find.byKey(_targetKey)),
        point: point ?? tester.getCenter(find.byKey(_targetKey)),
        viewId: tester.view.viewId,
      );
    }

    testWidgets('is covered when a sibling above the target claims the point', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _screen(
          targetChild: _opaque(),
          cover:
              Positioned.fill(child: _opaque(child: const SizedBox.expand())),
        ),
      );

      final HitProbe probe = probeTarget(tester);

      expect(probe.verdict, HitVerdict.covered);
      expect(probe.top, isA<RenderPointerListener>());
    });

    testWidgets('is reached when the target itself claims the point', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_screen(targetChild: _opaque()));

      expect(probeTarget(tester).verdict, HitVerdict.reached);
    });

    testWidgets('is reached when only a descendant of the target claims it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _screen(
            targetChild: Center(
                child: _opaque(child: const SizedBox(width: 10, height: 10)))),
      );

      expect(probeTarget(tester).verdict, HitVerdict.reached);
    });

    testWidgets('is ancestorOnly when only an ancestor of the target claims it',
        (
      WidgetTester tester,
    ) async {
      // A target with no hit-testable surface of its own is not covered by the
      // container that holds it; a cover is a sibling subtree painted above.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: _opaque(
                child: const SizedBox(
                  key: _targetKey,
                  width: 100,
                  height: 50,
                ),
              ),
            ),
          ),
        ),
      );

      final HitProbe probe = probeTarget(tester);

      expect(probe.verdict, HitVerdict.ancestorOnly);
      expect(probe.top, isA<RenderPointerListener>());
    });

    testWidgets('is platformOnly when the point lands outside every widget', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_screen(targetChild: _opaque()));

      final HitProbe probe = probeTarget(tester, point: const Offset(-50, -50));

      expect(probe.verdict, HitVerdict.platformOnly);
      expect(probe.top, isA<RenderView>());
    });
  });
}
