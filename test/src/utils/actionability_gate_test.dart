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

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e1',
            checkStable: false,
            checkReceivesEvents: false,
          ),
          completes,
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

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e7',
            checkStable: false,
            checkReceivesEvents: false,
          ),
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

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e2',
            checkStable: false,
            checkReceivesEvents: false,
          ),
          completes,
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

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e3',
            checkStable: false,
            checkReceivesEvents: false,
          ),
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

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e4',
            checkStable: false,
            checkReceivesEvents: false,
          ),
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

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e5',
            checkStable: false,
            checkReceivesEvents: false,
          ),
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
        await expectLater(
          ensureActionable(
            inside,
            ref: 'e6',
            checkStable: false,
            checkReceivesEvents: false,
          ),
          completes,
        );

        // Logical rect at (1000, 1000) sits OUTSIDE the 800x600 logical
        // viewport even though it would be inside the 1600x1200 physical
        // viewport — proves the divide-by-DPR step is applied.
        final RefEntry outside = _buildEntry(
          rect: const Rect.fromLTWH(1000, 1000, 50, 50),
          element: element,
        );
        await expectLater(
          ensureActionable(
            outside,
            ref: 'e7',
            checkStable: false,
            checkReceivesEvents: false,
          ),
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
      () async {
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

        await expectLater(
          ensureActionableForViews(
            entry,
            ref: 'e8',
            views: const <FlutterView>[],
            checkStable: false,
            checkReceivesEvents: false,
          ),
          completes,
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

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e9',
            checkStable: false,
            checkReceivesEvents: false,
          ),
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

    // -------------------------------------------------------------------------
    // (g) Stable gate — bounding box must not drift across two frames
    // -------------------------------------------------------------------------

    testWidgets(
      'stable-pass: passes when the live rect matches the entry rect within'
      ' 0.5px',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: ValueKey<String>('static-box'),
                  width: 100,
                  height: 100,
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(
          find.byKey(const ValueKey<String>('static-box')),
        );
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Offset topLeft = box.localToGlobal(Offset.zero);
        final Rect liveRect = topLeft & box.size;

        final RefEntry entry = _buildEntry(
          rect: liveRect,
          element: element,
        );

        // Kick off the gate, then pump so its internal `endOfFrame` await
        // resolves; finally drain the returned future to assert success.
        final Future<void> future = ensureActionable(
          entry,
          ref: 'e10',
          checkReceivesEvents: false,
        );
        await tester.pump();
        await expectLater(future, completes);
      },
    );

    testWidgets(
      'stable-fail: throws "not stable" when the widget rect drifts more'
      ' than 0.5px between two consecutive frames',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: _AnimatedMover(
                key: ValueKey<String>('mover'),
              ),
            ),
          ),
        );
        await tester.pump();

        final Element moverElement = tester.element(
          find.byKey(const ValueKey<String>('mover')),
        );
        final _AnimatedMoverState moverState =
            (moverElement as StatefulElement).state as _AnimatedMoverState;

        final Finder childFinder = find.byKey(
          const ValueKey<String>('moving-child'),
        );
        final Element childElement = tester.element(childFinder);
        final RenderBox childBox =
            childElement.findRenderObject()! as RenderBox;
        final Rect startRect =
            childBox.localToGlobal(Offset.zero) & childBox.size;

        final RefEntry entry = _buildEntry(
          rect: startRect,
          element: childElement,
        );

        // Kick off the gate. It captures the rect synchronously, awaits
        // `endOfFrame`, then re-resolves the rect. We jump the controller
        // forward AFTER the kick-off so the next pump's frame observes
        // the new transform offset (offset 0 → offset 100).
        final Future<void> future = ensureActionable(
          entry,
          ref: 'e11',
          checkReceivesEvents: false,
        );
        // expectLater observes the future-rejection BEFORE the pump so the
        // rejection does not propagate to the test zone as an unhandled
        // async error.
        final Future<void> expectation = expectLater(
          future,
          throwsA(
            isA<DuskActionabilityException>()
                .having(
                  (DuskActionabilityException e) => e.reason,
                  'reason',
                  startsWith('not stable'),
                )
                .having(
                  (DuskActionabilityException e) => e.message,
                  'message',
                  contains('not actionable: not stable'),
                ),
          ),
        );
        moverState.jumpTo(0.25);
        await tester.pump();
        await expectation;
      },
    );

    testWidgets(
      'stable-skip: passes when checkStable is false even on a widget that'
      ' just drifted',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: _AnimatedMover(
                key: ValueKey<String>('mover'),
              ),
            ),
          ),
        );
        await tester.pump();
        final Element moverElement = tester.element(
          find.byKey(const ValueKey<String>('mover')),
        );
        final _AnimatedMoverState moverState =
            (moverElement as StatefulElement).state as _AnimatedMoverState;

        final Finder childFinder = find.byKey(
          const ValueKey<String>('moving-child'),
        );
        final Element childElement = tester.element(childFinder);
        final RenderBox childBox =
            childElement.findRenderObject()! as RenderBox;
        final Rect startRect =
            childBox.localToGlobal(Offset.zero) & childBox.size;

        moverState.jumpTo(0.25);
        await tester.pump();

        final RefEntry entry = _buildEntry(
          rect: startRect,
          element: childElement,
        );

        // checkStable: false short-circuits — no `endOfFrame` await, so we
        // can synchronously await the gate without pump-future interleaving.
        await expectLater(
          ensureActionable(
            entry,
            ref: 'e12',
            checkStable: false,
            checkReceivesEvents: false,
          ),
          completes,
        );
      },
    );

    // -------------------------------------------------------------------------
    // (h) Receives-events gate — hit-test target must match the entry
    // -------------------------------------------------------------------------

    testWidgets(
      'receives-events-pass: passes when hit-test at rect.center lands on the'
      ' entry render object',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  key: const ValueKey<String>('hittable'),
                  color: const Color(0xFF2196F3),
                  width: 200,
                  height: 200,
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(
          find.byKey(const ValueKey<String>('hittable')),
        );
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Rect liveRect = box.localToGlobal(Offset.zero) & box.size;

        final RefEntry entry = _buildEntry(
          rect: liveRect,
          element: element,
        );

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e13',
            checkStable: false,
          ),
          completes,
        );
      },
    );

    testWidgets(
      'receives-events-fail: throws "obscured by other widget" when a modal'
      ' overlay covers the entry rect',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      key: const ValueKey<String>('below'),
                      color: const Color(0xFF2196F3),
                      width: 200,
                      height: 200,
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        key: const ValueKey<String>('overlay'),
                        color: const Color(0x88000000),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final Element belowElement = tester.element(
          find.byKey(const ValueKey<String>('below')),
        );
        final RenderBox belowBox =
            belowElement.findRenderObject()! as RenderBox;
        final Rect belowRect =
            belowBox.localToGlobal(Offset.zero) & belowBox.size;

        final RefEntry entry = _buildEntry(
          rect: belowRect,
          element: belowElement,
        );

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e14',
            checkStable: false,
          ),
          throwsA(
            isA<DuskActionabilityException>()
                .having(
                  (DuskActionabilityException e) => e.reason,
                  'reason',
                  startsWith('obscured by other widget'),
                )
                .having(
                  (DuskActionabilityException e) => e.message,
                  'message',
                  contains('obscured by other widget (top='),
                ),
          ),
        );
      },
    );

    testWidgets(
      'receives-events-skip: passes when checkReceivesEvents is false even on'
      ' an obscured widget',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      key: const ValueKey<String>('below'),
                      color: const Color(0xFF2196F3),
                      width: 200,
                      height: 200,
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: Container(color: const Color(0x88000000)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final Element belowElement = tester.element(
          find.byKey(const ValueKey<String>('below')),
        );
        final RenderBox belowBox =
            belowElement.findRenderObject()! as RenderBox;
        final Rect belowRect =
            belowBox.localToGlobal(Offset.zero) & belowBox.size;

        final RefEntry entry = _buildEntry(
          rect: belowRect,
          element: belowElement,
        );

        await expectLater(
          ensureActionable(
            entry,
            ref: 'e15',
            checkStable: false,
            checkReceivesEvents: false,
          ),
          completes,
        );
      },
    );

    // -------------------------------------------------------------------------
    // (i) Gate ordering — existing 3 gates fire before the new 2
    // -------------------------------------------------------------------------

    testWidgets(
      'reports "off-viewport" before "not stable" / "obscured by" when an'
      ' off-viewport rect is also unstable / obscured',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final RefEntry entry = _buildEntry(
          rect: const Rect.fromLTWH(5000, 5000, 50, 50),
          element: element,
        );

        await expectLater(
          ensureActionable(entry, ref: 'e16'),
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
    // (j) Reason substring contract — every reason carries its agent-parseable
    //     substring verbatim so prompt-side branching does not break.
    // -------------------------------------------------------------------------

    testWidgets(
      'every reason string contains its canonical agent-parseable substring',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Reuse the disabled-semantics widget for the "not enabled" reason.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  enabled: false,
                  label: 'reason-substring-target',
                  child: const SizedBox(width: 10, height: 10),
                ),
              ),
            ),
          ),
        );

        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel('reason-substring-target'),
        );
        final Element element = tester.element(find.byType(Scaffold));

        // 1. not enabled
        try {
          await ensureActionable(
            _buildEntry(
              rect: const Rect.fromLTWH(10, 10, 50, 50),
              element: element,
              node: node,
            ),
            ref: 'e17a',
            checkStable: false,
            checkReceivesEvents: false,
          );
          fail('expected "not enabled" throw');
        } on DuskActionabilityException catch (e) {
          expect(e.reason, contains('not enabled'));
        }

        // 2. zero rect
        try {
          await ensureActionable(
            _buildEntry(
              rect: const Rect.fromLTWH(10, 10, 0, 50),
              element: element,
            ),
            ref: 'e17b',
            checkStable: false,
            checkReceivesEvents: false,
          );
          fail('expected "zero rect" throw');
        } on DuskActionabilityException catch (e) {
          expect(e.reason, contains('zero rect'));
        }

        // 3. off-viewport
        try {
          await ensureActionable(
            _buildEntry(
              rect: const Rect.fromLTWH(5000, 5000, 50, 50),
              element: element,
            ),
            ref: 'e17c',
            checkStable: false,
            checkReceivesEvents: false,
          );
          fail('expected "off-viewport" throw');
        } on DuskActionabilityException catch (e) {
          expect(e.reason, contains('off-viewport'));
        }
      },
    );
  });
}

/// Stateful widget used by the stable-gate tests. Holds an
/// [AnimationController] driving an [AnimatedBuilder] that translates a
/// [SizedBox] horizontally. Calling [moveRight] flips the controller forward
/// so the next pumped frame advances the position; the gate then observes
/// the rect drift between the captured rect and the post-pump rect.
class _AnimatedMover extends StatefulWidget {
  const _AnimatedMover({super.key});

  @override
  State<_AnimatedMover> createState() => _AnimatedMoverState();
}

class _AnimatedMoverState extends State<_AnimatedMover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  void moveRight() {
    _controller.forward();
  }

  void jumpTo(double value) {
    _controller.value = value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Align(
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(_controller.value * 400, 0),
            child: const SizedBox(
              key: ValueKey<String>('moving-child'),
              width: 100,
              height: 100,
            ),
          ),
        );
      },
    );
  }
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
