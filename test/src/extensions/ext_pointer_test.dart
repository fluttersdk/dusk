import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_dusk/src/utils/actionability_gate.dart';
import 'package:fluttersdk_dusk/src/utils/error_envelope.dart';

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
        // alongside the future so frames advance under fake-async. Stable +
        // receives-events gates opt-out because registerForTesting mints a
        // synthetic rect that does not match the Center widget's live
        // geometry (Step 3.1 introduced the 4-gate; Step 3.2 made the gates
        // opt-out via params).
        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
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
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
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
        // Stable + receives-events gates opt-out: synthetic test rects do
        // not align with the live Center widget geometry.
        final future = aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{
            'startRef': startRef,
            'endRef': endRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
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

        // startRef is on-viewport (100,100,50,50) so it must clear the
        // gate before the handler checks endRef. With the Step 3.1 Stable
        // gate default-on, startRef would trip on stable (synthetic rect
        // vs live SizedBox.shrink geometry), masking the off-viewport
        // failure we want to assert on endRef. Opt out stable +
        // receives-events so startRef passes through to the off-viewport
        // check on endRef.
        final response = await aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{
            'startRef': startRef,
            'endRef': endRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
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
          parseMessageFromErrorDetail(response.errorDetail ?? ''),
          contains('missing required param "startRef"'),
        );
      },
    );

    test(
      '(d) missing endRef returns the original missing-param error',
      () async {
        final response = await aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{'startRef': 'e1'},
        );
        expect(response.result, isNull);
        expect(
          parseMessageFromErrorDetail(response.errorDetail ?? ''),
          contains('missing required param "endRef"'),
        );
      },
    );

    test(
      '(d) unknown startRef returns "not found in registry" error',
      () async {
        final response = await aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{'startRef': 'e9999', 'endRef': 'e8888'},
        );
        expect(response.result, isNull);
        expect(
          parseMessageFromErrorDetail(response.errorDetail ?? ''),
          contains('startRef "e9999" not found in registry'),
        );
      },
    );

    testWidgets(
      '(d) known startRef but unknown endRef returns endRef-not-found error',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final Element element = tester.element(find.byType(SizedBox));
        final String startRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(50, 50, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{'startRef': startRef, 'endRef': 'e9999'},
        );
        expect(response.result, isNull);
        expect(
          parseMessageFromErrorDetail(response.errorDetail ?? ''),
          contains('endRef "e9999" not found in registry'),
        );
      },
    );
  });

  group('aiTestHoverHandler additional error paths', () {
    setUp(RefRegistry.resetForTesting);

    test('missing ref returns missing-param error', () async {
      final response = await aiTestHoverHandler(
        'ext.dusk.hover',
        const <String, String>{},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
    });

    test('unknown ref returns not-found error', () async {
      final response = await aiTestHoverHandler(
        'ext.dusk.hover',
        const <String, String>{'ref': 'e9999'},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('not found in registry'));
    });
  });

  group('resolveRefForAction', () {
    setUp(RefRegistry.resetForTesting);

    test('returns null for empty ref', () {
      expect(resolveRefForAction(''), isNull);
    });

    test('returns null for unknown q-ref (no query stored)', () {
      expect(resolveRefForAction('q9999'), isNull);
    });

    test('returns null for unknown e-ref (no entry stored)', () {
      expect(resolveRefForAction('e9999'), isNull);
    });
  });

  group('registerPointerExtensions', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerPointerExtensions();
      registerPointerExtensions();
    });
  });

  group('aiTestTapHandler textfield post-dispatch path', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      'isTextField=true ref invokes _findEditableTextState after pointer dispatch',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TextField(
                  decoration: const InputDecoration(hintText: 'type here'),
                ),
              ),
            ),
          ),
        );

        final Element textFieldElement = tester.element(find.byType(TextField));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 50),
          element: textFieldElement,
          groupId: 'g-textfield',
          isTextField: true,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
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
  });

  // ---------------------------------------------------------------------------
  // Step 3.2 — snapshot-in-action-response (Playwright setIncludeSnapshot
  // parity). Every mutating action handler embeds the post-action YAML
  // snapshot under `snapshot` by default; `includeSnapshot: 'false'` opts
  // out for back-compat callers that do not want the extra payload.
  // ---------------------------------------------------------------------------

  group('aiTestTapHandler snapshot-in-response', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      'embeds snapshot field in success response by default',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('snap-tap'),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(ElevatedButton));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 80, 40),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(ref));
        expect(decoded['snapshot'], isA<String>());
        expect(decoded['snapshot'] as String, isNotEmpty);
      },
    );

    testWidgets(
      'omits snapshot field when includeSnapshot is false',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('no-snap'))),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(ref));
        expect(decoded.containsKey('snapshot'), isFalse);
      },
    );

    testWidgets(
      'snapshot YAML contains the tapped widget label',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('snap-content-target'),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(ElevatedButton));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 80, 40),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final String snapshot = decoded['snapshot'] as String;
        expect(snapshot, contains('snap-content-target'));
      },
    );
  });

  group('aiTestHoverHandler snapshot-in-response', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      'embeds snapshot field by default',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('hover-snap'))),
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
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['snapshot'], isA<String>());
      },
    );

    testWidgets(
      'omits snapshot when includeSnapshot is false',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('hover-nosnap'))),
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
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.containsKey('snapshot'), isFalse);
      },
    );

    testWidgets(
      'snapshot YAML reflects the post-hover tree contents',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('hover-content-marker'),
                ),
              ),
            ),
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
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['snapshot'] as String, contains('hover-content-marker'));
      },
    );
  });

  group('aiTestDragHandler snapshot-in-response', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      'embeds snapshot field in success response by default',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('drag-snap-target'))),
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

        final future = aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{
            'startRef': startRef,
            'endRef': endRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['startRef'], equals(startRef));
        expect(decoded['endRef'], equals(endRef));
        expect(decoded['snapshot'], isA<String>());
      },
    );

    testWidgets(
      'omits snapshot when includeSnapshot is false',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('drag-nosnap'))),
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

        final future = aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{
            'startRef': startRef,
            'endRef': endRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.containsKey('snapshot'), isFalse);
      },
    );

    testWidgets(
      'snapshot YAML reflects the post-drag tree',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('drag-content-marker'),
                ),
              ),
            ),
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

        final future = aiTestDragHandler(
          'ext.dusk.drag',
          <String, String>{
            'startRef': startRef,
            'endRef': endRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['snapshot'] as String, contains('drag-content-marker'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // D3 — aiTestDoubleClickHandler (dblclick)
  // ---------------------------------------------------------------------------

  group('aiTestDoubleClickHandler', () {
    setUp(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (a) Success path — double-click on an actionable widget returns ok envelope.
    // -------------------------------------------------------------------------

    testWidgets(
      '(a) actionable widget double-click returns ok envelope with ref',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int tapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GestureDetector(
                onTap: () => tapCount++,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestDoubleClickHandler(
          'ext.dusk.dblclick',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        // Two taps each with 50ms hold + 100ms inter-tap delay; pump through.
        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
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
    // (b) Actionability-blocked — off-viewport ref returns error.
    // -------------------------------------------------------------------------

    testWidgets(
      '(b) off-viewport double-click returns actionability error',
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

        final response = await aiTestDoubleClickHandler(
          'ext.dusk.dblclick',
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

    // -------------------------------------------------------------------------
    // (c) Missing ref param — returns missingParam error.
    // -------------------------------------------------------------------------

    test(
      '(c) missing ref param returns missing_param error envelope',
      () async {
        final response = await aiTestDoubleClickHandler(
          'ext.dusk.dblclick',
          <String, String>{},
        );

        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
      },
    );

    // -------------------------------------------------------------------------
    // (d) Snapshot embed — double-click with includeSnapshot:true returns snapshot.
    // -------------------------------------------------------------------------

    testWidgets(
      '(d) includeSnapshot:true embeds snapshot in response',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('dblclick-snap-test'))),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestDoubleClickHandler(
          'ext.dusk.dblclick',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'true',
          },
        );
        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.containsKey('snapshot'), isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // D1 — live-rect re-resolve before dispatch + opt-in --verify effect check.
  //
  // The bug: pointer verbs dispatched at the CACHED entry.rect.center captured
  // at gate time, not the element's live position after a rebuild. The fix is
  // purely additive between gate-pass and dispatch: re-resolve the live rect
  // via dispatchRectOf(entry) and dispatch at that center, falling back to
  // entry.rect.center when null (slivers/detached/synthetic-test entries).
  // ---------------------------------------------------------------------------

  group('dispatchRectOf', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      '(a) returns the live rect of a mounted, sized RenderBox',
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
                child: SizedBox(width: 120, height: 40, child: Text('live')),
              ),
            ),
          ),
        );

        final Element box = tester.element(find.byType(SizedBox));
        final RenderBox renderBox = box.renderObject! as RenderBox;
        final Offset liveTopLeft = renderBox.localToGlobal(Offset.zero);
        final Rect liveRect = liveTopLeft & renderBox.size;

        final RefEntry entry = RefEntry(
          // Deliberately stale cached rect, far from the live geometry.
          rect: const Rect.fromLTWH(500, 500, 10, 10),
          element: box,
          groupId: 'g',
          isTextField: false,
        );

        final Rect? dispatchRect = dispatchRectOf(entry);
        expect(dispatchRect, isNotNull);
        expect(dispatchRect!.center, equals(liveRect.center));
        expect(dispatchRect.center, isNot(equals(entry.rect.center)));
      },
    );

    testWidgets(
      '(c) returns null for a non-RenderBox (sliver) render object',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      const SizedBox(height: 50, child: Text('row')),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        );

        final Element sliver = tester.element(find.byType(SliverList));
        final RefEntry entry = RefEntry(
          rect: const Rect.fromLTWH(0, 0, 100, 50),
          element: sliver,
          groupId: 'g',
          isTextField: false,
        );

        expect(dispatchRectOf(entry), isNull);
      },
    );
  });

  group('aiTestTapHandler live-rect dispatch', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (b) onTap of a button whose host rebuilds into a shifted position fires.
    //
    // The cached rect points at the button's ORIGINAL position; the host then
    // rebuilds shifting the button. With the stale-rect dispatch the pointer
    // lands on empty space (counter stays 0); with the live-rect re-resolve it
    // lands on the button (counter increments). checkStable opts out because
    // the deliberate rebuild shifts the rect.
    // -------------------------------------------------------------------------

    testWidgets(
      '(b) tap fires onTap after the host rebuilds the button into a new slot',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int taps = 0;
        late StateSetter setOuter;
        double topPadding = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  setOuter = setState;
                  return Padding(
                    padding: EdgeInsets.only(top: topPadding),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: GestureDetector(
                        onTap: () => taps++,
                        child: const SizedBox(
                          width: 120,
                          height: 48,
                          child: ColoredBox(color: Color(0xFF0000FF)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        final Element gesture = tester.element(find.byType(GestureDetector));
        final RenderBox originalBox = gesture.renderObject! as RenderBox;
        final Rect cachedRect =
            originalBox.localToGlobal(Offset.zero) & originalBox.size;

        final String ref = RefRegistry.registerForTesting(
          rect: cachedRect,
          element: gesture,
          groupId: 'g',
          isTextField: false,
        );

        // Rebuild the host so the button slides down 200px. The cached rect is
        // now stale; only the live-rect re-resolve lands on the button.
        setOuter(() => topPadding = 200);
        await tester.pump();

        final RenderBox movedBox = gesture.renderObject! as RenderBox;
        final Rect liveRect =
            movedBox.localToGlobal(Offset.zero) & movedBox.size;
        expect(liveRect.center, isNot(equals(cachedRect.center)));

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        await future;

        expect(taps, equals(1));
      },
    );
  });

  group('aiTestTapHandler verify', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (d) verify:true returns changed:true when the target subtree changes
    // (a counter button whose own label increments).
    // -------------------------------------------------------------------------

    testWidgets(
      '(d) verify:true returns changed:true when the target subtree changes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int count = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) {
                    return ElevatedButton(
                      onPressed: () => setState(() => count++),
                      child: Text('Count: $count'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        final Element button = tester.element(find.byType(ElevatedButton));
        final SemanticsNode node =
            tester.getSemantics(find.byType(ElevatedButton));
        final RenderBox box = button.renderObject! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        final String ref = RefRegistry.register(
          rect: rect,
          element: button,
          groupId: 'g',
          isTextField: false,
          node: node,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'verify': 'true',
            'includeSnapshot': 'false',
            // The timing-sensitive gates (stable/receives-events) are not
            // under test here; opt out so the gate's `await endOfFrame` does
            // not outrun the fake-async pump budget. Matches the convention
            // used by every other handler test in this file.
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['changed'], isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (d) verify:true returns changed:false when nothing changes (inert button).
    // -------------------------------------------------------------------------

    testWidgets(
      '(d) verify:true returns changed:false when nothing changes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Inert'),
                ),
              ),
            ),
          ),
        );

        final Element button = tester.element(find.byType(ElevatedButton));
        final SemanticsNode node =
            tester.getSemantics(find.byType(ElevatedButton));
        final RenderBox box = button.renderObject! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        final String ref = RefRegistry.register(
          rect: rect,
          element: button,
          groupId: 'g',
          isTextField: false,
          node: node,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'verify': 'true',
            'includeSnapshot': 'false',
            // Gate timing is not under test here; opt out so the stable
            // gate's `await endOfFrame` does not outrun the fake-async pump
            // budget (see the changed:true case above).
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['changed'], isFalse);
      },
    );

    // -------------------------------------------------------------------------
    // (d) default call (no verify) payload is byte-identical to before: no
    // `changed` key, frozen success-shape preserved.
    // -------------------------------------------------------------------------

    testWidgets(
      '(d) default call (no verify) omits the changed field entirely',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('default'))),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.keys.toList(), equals(<String>['ref']));
        expect(decoded.containsKey('changed'), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // D7 — tap --until: after the tap settles, poll the element tree for the
  // expected text and report `untilMatched`. Confirms a navigation/state
  // change produced the text the agent was waiting for, or times out.
  // ---------------------------------------------------------------------------

  group('aiTestTapHandler --until', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'untilMatched=true when the tap reveals the expected text',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: _RevealOnTap(),
          ),
        );

        final Element element = tester.element(find.text('reveal'));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 120, 40),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
            'until': 'Revealed!',
          },
        );
        // Pump past the tap hold (50ms) + the two post-dispatch frames so the
        // onPressed setState rebuild renders "Revealed!" before the until poll
        // walks the tree; the poll then matches on its first iteration.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['untilMatched'], isTrue);
      },
    );

    testWidgets(
      'untilMatched=false when the expected text never appears (timeout)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('noop'),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(ElevatedButton));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 80, 40),
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
            'until': 'NeverAppears',
            'untilTimeoutMs': '300',
          },
        );
        // Pump past the tap settle (50ms + 2 frames) and the full 300ms poll
        // window so the real-timer delays inside the poll loop complete under
        // the fake clock; the text never appears, so untilMatched is false.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['untilMatched'], isFalse);
      },
    );
  });
}

/// Minimal widget whose button reveals a "Revealed!" Text on tap. Used by the
/// `--until` success test.
class _RevealOnTap extends StatefulWidget {
  @override
  State<_RevealOnTap> createState() => _RevealOnTapState();
}

class _RevealOnTapState extends State<_RevealOnTap> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ElevatedButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('reveal'),
            ),
            if (_revealed) const Text('Revealed!'),
          ],
        ),
      ),
    );
  }
}
