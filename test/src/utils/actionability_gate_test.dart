import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_dusk/src/utils/actionability_gate.dart';
import 'package:fluttersdk_dusk/src/utils/dusk_exceptions.dart';

/// Helper: build a [RefEntry] with the supplied [rect] and [node].
///
/// The [element] is required by [RefEntry] but the gate never reads it, so we
/// pump a throw-away widget and reuse its element across every entry.
RefEntry _buildEntry({
  required Rect rect,
  required Element element,
  SemanticsNode? node,
  bool isTextField = false,
}) {
  return RefEntry(
    rect: rect,
    element: element,
    groupId: 'test-group',
    isTextField: isTextField,
    node: node,
  );
}

void main() {
  group('DuskActionabilityException', () {
    test('extends DuskException and exposes ref + reason + message', () {
      const DuskActionabilityException exception = DuskActionabilityException(
        ref: 'e1',
        reason: 'not enabled',
      );

      expect(exception, isA<DuskException>());
      expect(exception, isA<Exception>());
      expect(exception.ref, equals('e1'));
      expect(exception.reason, equals('not enabled'));
      expect(
        exception.message,
        equals('Widget ref=e1 is not actionable: not enabled'),
      );
      expect(
        exception.toString(),
        contains('Widget ref=e1 is not actionable: not enabled'),
      );
    });
  });

  group('ensureActionable', () {
    setUp(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (a) Success path — enabled node, non-zero rect, inside viewport
    // -------------------------------------------------------------------------

    testWidgets(
      'passes silently when the entry is enabled, non-zero, and on-viewport',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  enabled: true,
                  label: 'enabled-button',
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );

        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel('enabled-button'),
        );
        final Element element = tester.element(find.byType(Scaffold));
        final RefEntry entry = _buildEntry(
          rect: const Rect.fromLTWH(10, 10, 50, 50),
          element: element,
          node: node,
        );

        expect(
          () => ensureActionable(entry, ref: 'e1'),
          returnsNormally,
        );
      },
    );

    // -------------------------------------------------------------------------
    // (b) Failure mode 1 — node.flagsCollection.isEnabled == Tristate.isFalse
    // -------------------------------------------------------------------------

    testWidgets(
      'throws DuskActionabilityException with reason "not enabled" when the'
      ' underlying SemanticsNode is disabled',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  enabled: false,
                  label: 'disabled-button',
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );

        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel('disabled-button'),
        );
        final Element element = tester.element(find.byType(Scaffold));
        final RefEntry entry = _buildEntry(
          rect: const Rect.fromLTWH(10, 10, 50, 50),
          element: element,
          node: node,
        );

        expect(
          () => ensureActionable(entry, ref: 'e7'),
          throwsA(
            isA<DuskActionabilityException>()
                .having((DuskActionabilityException e) => e.ref, 'ref', 'e7')
                .having(
                  (DuskActionabilityException e) => e.reason,
                  'reason',
                  'not enabled',
                )
                .having(
                  (DuskActionabilityException e) => e.message,
                  'message',
                  contains('not actionable: not enabled'),
                ),
          ),
        );
      },
    );

    testWidgets(
      'does NOT throw when the SemanticsNode has Tristate.none (unknown'
      ' enabled state)',
      (WidgetTester tester) async {
        // A bare Text() has no enabled flag set → Tristate.none.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('plain-text')),
            ),
          ),
        );

        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel('plain-text'),
        );
        final Element element = tester.element(find.byType(Scaffold));
        final RefEntry entry = _buildEntry(
          rect: const Rect.fromLTWH(10, 10, 50, 50),
          element: element,
          node: node,
        );

        expect(
          () => ensureActionable(entry, ref: 'e2'),
          returnsNormally,
        );
      },
    );

    // -------------------------------------------------------------------------
    // (c) Failure mode 2 — zero-area rect (width or height == 0)
    // -------------------------------------------------------------------------

    testWidgets(
      'throws with reason "zero rect" when the entry width is zero',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final RefEntry entry = _buildEntry(
          rect: const Rect.fromLTWH(10, 10, 0, 50),
          element: element,
        );

        expect(
          () => ensureActionable(entry, ref: 'e3'),
          throwsA(
            isA<DuskActionabilityException>()
                .having(
                  (DuskActionabilityException e) => e.reason,
                  'reason',
                  'zero rect',
                )
                .having(
                  (DuskActionabilityException e) => e.message,
                  'message',
                  contains('Widget ref=e3 is not actionable: zero rect'),
                ),
          ),
        );
      },
    );

    testWidgets(
      'throws with reason "zero rect" when the entry height is zero',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final RefEntry entry = _buildEntry(
          rect: const Rect.fromLTWH(10, 10, 50, 0),
          element: element,
        );

        expect(
          () => ensureActionable(entry, ref: 'e4'),
          throwsA(
            isA<DuskActionabilityException>().having(
              (DuskActionabilityException e) => e.reason,
              'reason',
              'zero rect',
            ),
          ),
        );
      },
    );

    // -------------------------------------------------------------------------
    // (d) Failure mode 3 — rect does NOT intersect the viewport
    // -------------------------------------------------------------------------

    testWidgets(
      'throws with reason "off-viewport (rect=..., viewport=...)" when the'
      ' rect lies entirely outside the current view',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        // Viewport is (0,0,800,600); place the rect way off to the right.
        final RefEntry entry = _buildEntry(
          rect: const Rect.fromLTWH(2000, 2000, 50, 50),
          element: element,
        );

        expect(
          () => ensureActionable(entry, ref: 'e5'),
          throwsA(
            isA<DuskActionabilityException>()
                .having(
                  (DuskActionabilityException e) => e.reason,
                  'reason',
                  startsWith('off-viewport'),
                )
                .having(
                  (DuskActionabilityException e) => e.message,
                  'message',
                  allOf(
                    contains('Widget ref=e5 is not actionable: off-viewport'),
                    contains('rect='),
                    contains('viewport='),
                  ),
                ),
          ),
        );
      },
    );

    testWidgets(
      'honours devicePixelRatio when computing viewport bounds',
      (WidgetTester tester) async {
        // Physical 1600x1200 at DPR 2.0 → logical viewport 800x600.
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));

        // Logical rect at (100, 100, 50, 50) sits comfortably inside 800x600.
        final RefEntry inside = _buildEntry(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
        );
        expect(
          () => ensureActionable(inside, ref: 'e6'),
          returnsNormally,
        );

        // Logical rect at (1000, 1000) sits OUTSIDE the 800x600 logical
        // viewport even though it would be inside the 1600x1200 physical
        // viewport — proves the divide-by-DPR step is applied.
        final RefEntry outside = _buildEntry(
          rect: const Rect.fromLTWH(1000, 1000, 50, 50),
          element: element,
        );
        expect(
          () => ensureActionable(outside, ref: 'e7'),
          throwsA(
            isA<DuskActionabilityException>().having(
              (DuskActionabilityException e) => e.reason,
              'reason',
              startsWith('off-viewport'),
            ),
          ),
        );
      },
    );

    // -------------------------------------------------------------------------
    // (e) Edge case — platformDispatcher.views is empty → return gracefully
    // -------------------------------------------------------------------------

    test(
      'returns gracefully (no throw) when platformDispatcher.views is empty',
      () {
        // We cannot easily empty platformDispatcher.views from a test, but
        // we can call ensureActionableForViews directly with an empty view
        // list to exercise the same code path the production gate uses.
        final RefEntry entry = RefEntry(
          rect: const Rect.fromLTWH(2000, 2000, 50, 50),
          // ignore: invalid_use_of_visible_for_testing_member
          element: _StubElement(),
          groupId: 'g',
          isTextField: false,
        );

        expect(
          () => ensureActionableForViews(
            entry,
            ref: 'e8',
            views: const <FlutterView>[],
          ),
          returnsNormally,
        );
      },
    );

    // -------------------------------------------------------------------------
    // (f) Check ordering — enabled check fires before rect checks
    // -------------------------------------------------------------------------

    testWidgets(
      'reports "not enabled" before "zero rect" when both conditions hold',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  enabled: false,
                  label: 'disabled-and-empty',
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );

        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel('disabled-and-empty'),
        );
        final Element element = tester.element(find.byType(Scaffold));
        final RefEntry entry = _buildEntry(
          // Zero rect AND disabled — gate should surface "not enabled" first
          // because that is the most actionable signal for the agent.
          rect: const Rect.fromLTWH(10, 10, 0, 0),
          element: element,
          node: node,
        );

        expect(
          () => ensureActionable(entry, ref: 'e9'),
          throwsA(
            isA<DuskActionabilityException>().having(
              (DuskActionabilityException e) => e.reason,
              'reason',
              'not enabled',
            ),
          ),
        );
      },
    );
  });
}

/// Minimal [Element] stub used by the platformDispatcher.views-empty test
/// where we only need a non-null reference to satisfy [RefEntry] and never
/// actually render anything.
class _StubElement extends ComponentElement {
  _StubElement() : super(const _StubWidget());

  @override
  Widget build() => const SizedBox.shrink();
}

class _StubWidget extends Widget {
  const _StubWidget();

  @override
  Element createElement() => _StubElement();
}
