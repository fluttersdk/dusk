import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';
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
}
