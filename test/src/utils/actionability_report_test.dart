import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_dusk/src/utils/actionability_gate.dart';

/// Verifies that the receives-events check says what it actually knows.
///
/// The check hit-tests the target's centre and throws when something else is
/// on top. On Flutter Web's debug build the hit-test routinely comes back
/// carrying only the root render view, because DWDS pipes it through a
/// snapshot view that does not mirror the live element subtree. Breaking
/// every valid tap on that artifact would be the worse failure, so the gate
/// proceeds. It used to proceed SILENTLY, which is how a fill printed a
/// green tick four times onto a row covered by a pinned footer.
RefEntry _entry({required Rect rect, required Element element}) {
  return RefEntry(
    rect: rect,
    element: element,
    groupId: 'test-group',
    isTextField: false,
  );
}

void main() {
  group('ensureActionable report', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets('confirms receipt when the hit-test reaches the target', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(width: 200, height: 200),
              ),
            ),
          ),
        ),
      );

      final Element element = tester.element(find.byType(GestureDetector));
      final RenderBox box = element.findRenderObject()! as RenderBox;

      final ActionabilityReport report = await ensureActionable(
        _entry(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
        ),
        ref: 'e1',
        checkStable: false,
      );

      expect(report.receivesEvents, equals(ReceivesEvents.confirmed));
      expect(report.why, isNull);
      expect(report.overlapCandidates, isEmpty);
    });

    testWidgets(
        'reports indeterminate when the hit-test reaches only the '
        'root view', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // An empty tree, so the hit-test at the synthetic rect's centre finds
      // nothing but the root render view. That is the shape Flutter Web's
      // debug build produces for a real widget.
      await tester.pumpWidget(const SizedBox.shrink());

      final Element element = tester.element(find.byType(SizedBox));

      final ActionabilityReport report = await ensureActionable(
        _entry(rect: const Rect.fromLTWH(100, 100, 50, 50), element: element),
        ref: 'e1',
        checkStable: false,
      );

      expect(report.receivesEvents, equals(ReceivesEvents.indeterminate));
      expect(report.why, isNotNull);
      expect(report.why, contains('root'));
    });

    testWidgets('records the opt-out rather than claiming confirmation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final Element element = tester.element(find.byType(SizedBox));

      final ActionabilityReport report = await ensureActionable(
        _entry(rect: const Rect.fromLTWH(10, 10, 50, 50), element: element),
        ref: 'e1',
        checkStable: false,
        checkReceivesEvents: false,
      );

      expect(report.receivesEvents, equals(ReceivesEvents.skipped));
    });
  });

  group('occlusionCandidatesFor', () {
    testWidgets('names a later-painted sibling covering the target', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    key: ValueKey<String>('row'),
                    width: 200,
                    height: 200,
                  ),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    key: ValueKey<String>('footer'),
                    width: 300,
                    height: 300,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final RenderBox target = tester
          .element(find.byKey(const ValueKey<String>('row')))
          .findRenderObject()! as RenderBox;

      final List<String> candidates = occlusionCandidatesFor(
        target,
        target.localToGlobal(Offset.zero) & target.size,
      );

      expect(candidates, isNotEmpty);
    });

    testWidgets('is empty when nothing overlaps', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      final RenderBox target = tester
          .element(find.byType(SizedBox).first)
          .findRenderObject()! as RenderBox;

      expect(
        occlusionCandidatesFor(
          target,
          target.localToGlobal(Offset.zero) & target.size,
        ),
        isEmpty,
      );
    });
  });
}
