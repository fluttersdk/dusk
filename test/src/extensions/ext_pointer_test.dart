import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// Tests for the actionability gate wired into [aiTestTapHandler],
/// [aiTestHoverHandler], and [aiTestDragHandler] (Step 15).
///
/// Each handler resolves its ref(s) via [RefRegistry], then defers to
/// `ensureActionable` (Step 14) before dispatching the pointer event. A
/// failed gate must short-circuit with a `ServiceExtensionResponse.error`
/// whose `errorDetail` carries the descriptive
/// `"Widget ref=... is not actionable: ..."` message verbatim.
///
/// We use [RefRegistry.registerForTesting] to seed entries with precise
/// rects so we can drive the failure modes deterministically — the
/// production snapshot path is exercised end-to-end in the integration
/// suite, not here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aiTestTapHandler actionability gate', () {
    setUp(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (a) Actionable widget tap succeeds
    // -------------------------------------------------------------------------

    testWidgets(
      '(a) actionable widget tap returns ok envelope',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('hello'))),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        // The handler awaits a 50ms delay and two endOfFrame ticks; pump
        // alongside the future so frames advance under fake-async.
        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{'ref': ref},
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(ref));
      },
    );

    // -------------------------------------------------------------------------
    // (b) Off-viewport widget tap fails fast with descriptive error
    // -------------------------------------------------------------------------

    testWidgets(
      '(b) off-viewport tap returns descriptive actionability error',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(5000, 5000, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{'ref': ref},
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          allOf(
            contains('Widget ref=$ref is not actionable'),
            contains('off-viewport'),
          ),
        );
      },
    );

    testWidgets(
      '(b) disabled widget tap returns "not enabled" actionability error',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
        final String ref = RefRegistry.register(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
          node: node,
        );

        final response = await aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{'ref': ref},
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          contains('Widget ref=$ref is not actionable: not enabled'),
        );
      },
    );

    testWidgets(
      '(b) zero-rect tap returns "zero rect" actionability error',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(10, 10, 0, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{'ref': ref},
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          contains('Widget ref=$ref is not actionable: zero rect'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // (c) Pre-existing guard clauses still take precedence over the gate
    // -------------------------------------------------------------------------

    test(
      '(c) missing ref param still returns the original missing-param error',
      () async {
        final response =
            await aiTestTapHandler('ext.dusk.tap', <String, String>{});
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
      },
    );

    test(
      '(c) unknown ref still returns the original not-found error',
      () async {
        final response = await aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{'ref': 'e9999'},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('not found in registry'));
      },
    );
  });

  group('aiTestHoverHandler actionability gate', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      '(a) actionable widget hover returns ok envelope',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('hover-target'))),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(50, 50, 60, 60),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestHoverHandler(
          'ext.dusk.hover',
          <String, String>{'ref': ref},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
      },
    );

    testWidgets(
      '(b) off-viewport hover returns descriptive actionability error',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(5000, 5000, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await aiTestHoverHandler(
          'ext.dusk.hover',
          <String, String>{'ref': ref},
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          allOf(
            contains('Widget ref=$ref is not actionable'),
            contains('off-viewport'),
          ),
        );
      },
    );
  });

  group('aiTestDragHandler actionability gate', () {
    setUp(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (a) Both ends actionable → drag returns ok envelope
    // -------------------------------------------------------------------------

    testWidgets(
      '(a) both endpoints actionable → drag returns ok envelope',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('drag-host'))),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String startRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(50, 50, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );
        final String endRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(300, 300, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        // Drag handler awaits 5 × 16ms delays plus two endOfFrame ticks.
        final future = aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{'startRef': startRef, 'endRef': endRef},
        );
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['startRef'], equals(startRef));
        expect(decoded['endRef'], equals(endRef));
      },
    );

    // -------------------------------------------------------------------------
    // (c) Off-viewport drag fails fast — both startRef and endRef are gated
    // -------------------------------------------------------------------------

    testWidgets(
      '(c) off-viewport startRef short-circuits with descriptive error',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final String startRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(5000, 5000, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );
        final String endRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{'startRef': startRef, 'endRef': endRef},
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          allOf(
            contains('Widget ref=$startRef is not actionable'),
            contains('off-viewport'),
          ),
        );
      },
    );

    testWidgets(
      '(c) off-viewport endRef short-circuits with descriptive error',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final String startRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );
        final String endRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(5000, 5000, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{'startRef': startRef, 'endRef': endRef},
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          allOf(
            contains('Widget ref=$endRef is not actionable'),
            contains('off-viewport'),
          ),
        );
      },
    );

    // -------------------------------------------------------------------------
    // (d) Pre-existing guard clauses still take precedence
    // -------------------------------------------------------------------------

    test(
      '(d) missing startRef still returns the original missing-param error',
      () async {
        final response = await aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{'endRef': 'e1'},
        );
        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          contains('missing required param "startRef"'),
        );
      },
    );
  });
}
