import 'dart:convert';
import 'dart:developer';

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
  // D1 — live-rect re-resolve before dispatch + the always-on effect check.
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

  group('aiTestTapHandler effect', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (d) effect.changed is true when the target subtree changes
    // (a counter button whose own label increments).
    // -------------------------------------------------------------------------

    testWidgets(
      '(d) reports changed:true when the target subtree changes',
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
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['kind'], equals('treeChanged'));
        expect(effect['changed'], isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (d) effect.changed is false when nothing changes (inert button).
    // -------------------------------------------------------------------------

    testWidgets(
      '(d) reports changed:false when nothing changes',
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
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['kind'], equals('treeChanged'));
        expect(effect['changed'], isFalse);
      },
    );

    // -------------------------------------------------------------------------
    // (d) the block needs no opt-in: a default call carries it too, which
    // is the point. An agent cannot forget to ask whether the tap landed.
    // -------------------------------------------------------------------------

    testWidgets(
      '(d) a default call carries the effect block',
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
        expect(
          (decoded['effect'] as Map<String, dynamic>)['kind'],
          equals('treeChanged'),
        );
        // This call opts out of the receives-events gate (synthetic rect),
        // and the payload records that rather than letting a clean pass
        // read as a confirmation the gate never made.
        expect(
          (decoded['checks'] as Map<String, dynamic>)['receivesEvents'],
          equals('skipped'),
        );
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

  // ---------------------------------------------------------------------------
  // Gate reporting
  // ---------------------------------------------------------------------------

  group('aiTestTapHandler checks', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      'records an unprovable receives-events check on the payload',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Nothing painted, so the hit-test reaches only the root render
        // view. That is the shape Flutter Web's debug build produces for a
        // real widget, and it used to pass as a silent clean gate.
        await tester.pumpWidget(const SizedBox.shrink());

        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: tester.element(find.byType(SizedBox)),
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': ref,
            'checkStable': 'false',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> checks =
            decoded['checks'] as Map<String, dynamic>;
        expect(checks['receivesEvents'], equals('indeterminate'));
        expect(checks['why'], contains('root'));
        expect(checks['hint'], contains('may have landed on something else'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Frame starvation — the hidden-page path
  // ---------------------------------------------------------------------------

  group('aiTestTapHandler under frame starvation', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      'tap resolves when the engine produces no frames',
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

        // `runAsync` swaps the fake clock for the real one AND stops the
        // harness from pumping, which is exactly what a backgrounded Chrome
        // tab does: `document.visibilityState: "hidden"` disables frame
        // production, so every `endOfFrame` the handler awaits never
        // completes. The handler must fall through on its own timer rather
        // than block until the caller's shell timeout kills it.
        final ServiceExtensionResponse? response =
            await tester.runAsync<ServiceExtensionResponse?>(
          () => aiTestTapHandler(
            'ext.dusk.tap',
            <String, String>{
              'ref': ref,
              'checkStable': 'false',
              'checkReceivesEvents': 'false',
              'includeSnapshot': 'false',
            },
          )
              .then<ServiceExtensionResponse?>(
                (ServiceExtensionResponse r) => r,
              )
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () => null,
              ),
        );

        expect(
          response,
          isNotNull,
          reason: 'tap must not block forever when no frame is produced',
        );
        expect(response!.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(ref));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Right-click and triple-click: the two verbs whose handlers had no test.
  // Both settle through the bounded frame awaits, so a starved engine returns
  // instead of hanging, and both stamp the response through duskResult.
  // ---------------------------------------------------------------------------

  group('aiTestRightClickHandler', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('an actionable widget returns the right-button envelope', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 100, height: 100)),
        ),
      );

      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(100, 100, 50, 50),
        element: tester.element(find.byType(Scaffold)),
        groupId: 'g',
        isTextField: false,
      );

      final Future<ServiceExtensionResponse> future = aiTestRightClickHandler(
        'ext.dusk.right_click',
        <String, String>{
          'ref': ref,
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'includeSnapshot': 'false',
        },
      );
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ServiceExtensionResponse response = await future;

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['ref'], equals(ref));
      expect(decoded['button'], equals('right'));
    });

    testWidgets('an unknown ref returns a stale envelope', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      final ServiceExtensionResponse response = await aiTestRightClickHandler(
        'ext.dusk.right_click',
        const <String, String>{'ref': 'e999'},
      );

      expect(response.result, isNull);
      expect(response.errorDetail, isNotNull);
    });
  });

  group('aiTestTripleClickHandler', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('an actionable widget returns clickCount 3', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 100, height: 100)),
        ),
      );

      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(100, 100, 50, 50),
        element: tester.element(find.byType(Scaffold)),
        groupId: 'g',
        isTextField: false,
      );

      final Future<ServiceExtensionResponse> future = aiTestTripleClickHandler(
        'ext.dusk.triple_click',
        <String, String>{
          'ref': ref,
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'includeSnapshot': 'false',
        },
      );
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ServiceExtensionResponse response = await future;

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['ref'], equals(ref));
      expect(decoded['clickCount'], equals(3));
    });
  });

  group('the checks block reaches every verb that runs the gate', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    /// A tree with nothing painted at the ref's rect, so the hit-test
    /// reaches only the root render view. That is the shape Flutter Web's
    /// debug build produces for a real widget, and it is the state the
    /// block exists to report.
    Future<String> unprovableRef(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SizedBox.shrink());
      return RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(100, 100, 50, 50),
        element: tester.element(find.byType(SizedBox)),
        groupId: 'g',
        isTextField: false,
      );
    }

    Future<Map<String, dynamic>> drive(
      WidgetTester tester,
      Future<ServiceExtensionResponse> Function() call,
    ) async {
      final Future<ServiceExtensionResponse> future = call();
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return jsonDecode((await future).result!) as Map<String, dynamic>;
    }

    testWidgets('hover reports it', (WidgetTester tester) async {
      final String ref = await unprovableRef(tester);
      final Map<String, dynamic> decoded = await drive(
        tester,
        () => aiTestHoverHandler('ext.dusk.hover', <String, String>{
          'ref': ref,
          'checkStable': 'false',
          'includeSnapshot': 'false',
        }),
      );

      expect(
        (decoded['checks'] as Map<String, dynamic>)['receivesEvents'],
        equals('indeterminate'),
      );
    });

    testWidgets('dblclick reports it', (WidgetTester tester) async {
      final String ref = await unprovableRef(tester);
      final Map<String, dynamic> decoded = await drive(
        tester,
        () => aiTestDoubleClickHandler('ext.dusk.dblclick', <String, String>{
          'ref': ref,
          'checkStable': 'false',
          'includeSnapshot': 'false',
        }),
      );

      expect(
        (decoded['checks'] as Map<String, dynamic>)['receivesEvents'],
        equals('indeterminate'),
      );
    });

    testWidgets('right_click reports it', (WidgetTester tester) async {
      final String ref = await unprovableRef(tester);
      final Map<String, dynamic> decoded = await drive(
        tester,
        () => aiTestRightClickHandler('ext.dusk.right_click', <String, String>{
          'ref': ref,
          'checkStable': 'false',
          'includeSnapshot': 'false',
        }),
      );

      expect(
        (decoded['checks'] as Map<String, dynamic>)['receivesEvents'],
        equals('indeterminate'),
      );
    });

    testWidgets('triple_click reports it', (WidgetTester tester) async {
      final String ref = await unprovableRef(tester);
      final Map<String, dynamic> decoded = await drive(
        tester,
        () =>
            aiTestTripleClickHandler('ext.dusk.triple_click', <String, String>{
          'ref': ref,
          'checkStable': 'false',
          'includeSnapshot': 'false',
        }),
      );

      expect(
        (decoded['checks'] as Map<String, dynamic>)['receivesEvents'],
        equals('indeterminate'),
      );
    });

    testWidgets('drag reports it for either end', (WidgetTester tester) async {
      final String ref = await unprovableRef(tester);
      final Map<String, dynamic> decoded = await drive(
        tester,
        () => aiTestDragHandler('ext.dusk.drag', <String, String>{
          'startRef': ref,
          'endRef': ref,
          'checkStable': 'false',
          'includeSnapshot': 'false',
        }),
      );

      expect(
        (decoded['checks'] as Map<String, dynamic>)['receivesEvents'],
        equals('indeterminate'),
      );
    });

    test('a confirmed gate stamps nothing', () {
      // The healthy path carries no extra bytes, so the key's presence is
      // itself the signal. Asserted on the shared helper rather than through
      // a handler, because every verb reaches it the same way.
      final Map<String, dynamic> payload = <String, dynamic>{'ref': 'e1'};
      stampChecks(
        payload,
        const ActionabilityReport(receivesEvents: ReceivesEvents.confirmed),
      );

      expect(payload.containsKey('checks'), isFalse);
    });

    test('a skipped gate is still worth saying out loud', () {
      // `--no-checkReceivesEvents` is a caller opting out, not a pass; a
      // response that looked identical to a confirmed one would hide it.
      final Map<String, dynamic> payload = <String, dynamic>{'ref': 'e1'};
      stampChecks(
        payload,
        const ActionabilityReport(receivesEvents: ReceivesEvents.skipped),
      );

      expect(
        (payload['checks'] as Map<String, dynamic>)['receivesEvents'],
        equals('skipped'),
      );
    });
  });

  group('aiTestTripleClickHandler gate refusal', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('a zero-rect target is refused with the frozen substring', (
      WidgetTester tester,
    ) async {
      // Agents branch on the reason substring, so every verb that runs the
      // gate has to surface it in the same envelope shape.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      final String ref = RefRegistry.registerForTesting(
        rect: Rect.zero,
        element: tester.element(find.byType(Scaffold)),
        groupId: 'g',
        isTextField: false,
      );

      final ServiceExtensionResponse response = await aiTestTripleClickHandler(
        'ext.dusk.triple_click',
        <String, String>{'ref': ref},
      );

      expect(response.result, isNull);
      expect(response.errorDetail, contains('zero rect'));
    });
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
