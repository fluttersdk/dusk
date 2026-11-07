import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_dusk/src/utils/actionability_gate.dart';
import 'package:fluttersdk_dusk/src/utils/dusk_register.dart';
import 'package:fluttersdk_dusk/src/utils/error_envelope.dart';

void _useSmallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A column of `Save` buttons, one per key. Swapping a key replaces the
/// button's whole element subtree, which is what a rebuild that recreates a
/// control looks like to a snapshot ref.
Widget _saveScreen(Map<Key, VoidCallback> buttons) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final MapEntry<Key, VoidCallback> button in buttons.entries)
            KeyedSubtree(
              key: button.key,
              child: Semantics(
                container: true,
                button: true,
                label: 'Save',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: button.value,
                  child: const SizedBox(width: 160, height: 40),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A single `Save` button under [key], so swapping the key replaces its
/// element subtree.
Widget _saveButton(Key key, VoidCallback onTap) {
  return KeyedSubtree(
    key: key,
    child: Semantics(
      container: true,
      button: true,
      label: 'Save',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox(width: 160, height: 40),
      ),
    ),
  );
}

/// A `Save` button with no [Navigator] above it, so it lives on no route.
Widget _routelessSaveScreen(Key key, VoidCallback onTap) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: _saveButton(key, onTap),
    ),
  );
}

/// The example app's merged-boundary fixture: a 300x120 `MergeSemantics` whose
/// only control, a 72x28 `Skip intro` button, sits bottom-right. The merged
/// node's centre is empty space beside it, yet hit-testable because the
/// boundary paints a background, as the example app's does.
Widget _mergedBoundaryScreen() {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: MergeSemantics(
          key: const Key('merged-boundary'),
          child: Container(
            width: 300,
            height: 120,
            color: const Color(0xFFE0F2F1),
            child: Stack(
              children: <Widget>[
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Semantics(
                    button: true,
                    label: 'Skip intro',
                    onTap: () {},
                    excludeSemantics: true,
                    child: const SizedBox(width: 72, height: 28),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

List<String> _refsFor(String snapshot, String label) {
  return RegExp('"$label" \\[ref=(e\\d+)\\]')
      .allMatches(snapshot)
      .map((RegExpMatch m) => m.group(1)!)
      .toList();
}

/// Taps [ref] through the registration wrapper, so the call runs in the zone
/// that collects re-resolved refs, pumping frames while the handler awaits.
Future<ServiceExtensionResponse> _pumpTap(
  WidgetTester tester,
  String ref,
) async {
  final Future<ServiceExtensionResponse> future =
      wrapDuskHandler(aiTestTapHandler)(
    'ext.dusk.tap',
    <String, String>{
      'ref': ref,
      'includeSnapshot': 'false',
    },
  );
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return future;
}

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

  group('resolveRefForAction re-resolution', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'a replaced e-ref taps the equal-label widget that took its place',
      (WidgetTester tester) async {
        _useSmallView(tester);
        int oldTaps = 0;
        int newTaps = 0;
        await tester.pumpWidget(
          _saveScreen(<Key, VoidCallback>{
            const ValueKey<String>('old'): () => oldTaps++,
          }),
        );
        final String ref = _refsFor(
          (await duskSnapBuild())['snapshot'] as String,
          'Save',
        ).single;

        await tester.pumpWidget(
          _saveScreen(<Key, VoidCallback>{
            const ValueKey<String>('new'): () => newTaps++,
          }),
        );
        expect(RefRegistry.lookup(ref)!.element.mounted, isFalse);

        final ServiceExtensionResponse response = await _pumpTap(tester, ref);

        expect(response.errorDetail, isNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(ref));
        expect(decoded['reresolved'], equals(<String>[ref]));
        expect(newTaps, equals(1));
        expect(oldTaps, equals(0));
        expect(RefRegistry.lookup(ref)!.element.mounted, isTrue);
      },
    );

    testWidgets(
      'an e-ref whose label lost a namesake stays defunct',
      (WidgetTester tester) async {
        _useSmallView(tester);
        int taps = 0;
        await tester.pumpWidget(
          _saveScreen(<Key, VoidCallback>{
            const ValueKey<String>('a'): () => taps++,
            const ValueKey<String>('b'): () => taps++,
          }),
        );
        final String ref = _refsFor(
          (await duskSnapBuild())['snapshot'] as String,
          'Save',
        ).first;

        await tester.pumpWidget(
          _saveScreen(<Key, VoidCallback>{
            const ValueKey<String>('c'): () => taps++,
          }),
        );

        final ServiceExtensionResponse response = await _pumpTap(tester, ref);

        expect(response.result, isNull);
        expect(
          response.errorDetail,
          contains('defunct (element no longer mounted)'),
        );
        expect(taps, equals(0));
      },
    );

    testWidgets(
      'an e-ref is not relocated onto an equal-label widget on another route',
      (WidgetTester tester) async {
        _useSmallView(tester);
        final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
        int firstTaps = 0;
        int secondTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(
              body: _saveButton(
                const ValueKey<String>('first'),
                () => firstTaps++,
              ),
            ),
          ),
        );
        final String ref = _refsFor(
          (await duskSnapBuild())['snapshot'] as String,
          'Save',
        ).single;

        navigator.currentState!.pushReplacement(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => Scaffold(
              body: _saveButton(
                const ValueKey<String>('second'),
                () => secondTaps++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(RefRegistry.lookup(ref)!.element.mounted, isFalse);

        final ServiceExtensionResponse response = await _pumpTap(tester, ref);

        expect(response.result, isNull);
        expect(
          response.errorDetail,
          contains('defunct (element no longer mounted)'),
        );
        expect(response.errorDetail, isNot(contains('reresolved')));
        expect(secondTaps, equals(0));
        expect(firstTaps, equals(0));
      },
    );

    testWidgets(
      'an e-ref minted outside any route still relocates',
      (WidgetTester tester) async {
        _useSmallView(tester);
        int oldTaps = 0;
        int newTaps = 0;
        await tester.pumpWidget(
          _routelessSaveScreen(
            const ValueKey<String>('old'),
            () => oldTaps++,
          ),
        );
        final String ref = _refsFor(
          (await duskSnapBuild())['snapshot'] as String,
          'Save',
        ).single;
        expect(RefRegistry.lookupBinding(ref)!.route, isNull);

        await tester.pumpWidget(
          _routelessSaveScreen(
            const ValueKey<String>('new'),
            () => newTaps++,
          ),
        );
        expect(RefRegistry.lookup(ref)!.element.mounted, isFalse);

        final ServiceExtensionResponse response = await _pumpTap(tester, ref);

        expect(response.errorDetail, isNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['reresolved'], equals(<String>[ref]));
        expect(newTaps, equals(1));
        expect(oldTaps, equals(0));
      },
    );

    testWidgets(
      'a still-mounted e-ref taps as before and reports no re-resolution',
      (WidgetTester tester) async {
        _useSmallView(tester);
        int taps = 0;
        await tester.pumpWidget(
          _saveScreen(<Key, VoidCallback>{
            const ValueKey<String>('only'): () => taps++,
          }),
        );
        final String ref = _refsFor(
          (await duskSnapBuild())['snapshot'] as String,
          'Save',
        ).single;
        final RefEntry before = RefRegistry.lookup(ref)!;

        final ServiceExtensionResponse response = await _pumpTap(tester, ref);

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(ref));
        expect(decoded.containsKey('reresolved'), isFalse);
        expect(taps, equals(1));
        expect(RefRegistry.lookup(ref), same(before));
      },
    );
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
  // Tap point versus the control's own area (#60)
  // ---------------------------------------------------------------------------

  group('aiTestTapHandler tapPointOutsideOwner', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'a merged boundary whose tap carrier sits off-centre reports the point',
      (WidgetTester tester) async {
        _useSmallView(tester);
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_mergedBoundaryScreen());
          final String snapshot = (await duskSnapBuild())['snapshot'] as String;
          final String ref = _refsFor(snapshot, 'Skip intro').single;

          final ServiceExtensionResponse response = await _pumpTap(tester, ref);

          expect(response.result, isNotNull, reason: response.errorDetail);
          final Map<String, dynamic> decoded =
              jsonDecode(response.result!) as Map<String, dynamic>;
          expect(decoded, contains('tapPointOutsideOwner'));
          final Map<String, dynamic> outside =
              decoded['tapPointOutsideOwner'] as Map<String, dynamic>;

          // The tap lands on the boundary's centre, which is the very gap the
          // gate confirms and the control's own area does not cover.
          final Finder boundary = find.byKey(const Key('merged-boundary'));
          final Offset centre = tester.getCenter(boundary);
          final Map<String, dynamic> point =
              outside['point'] as Map<String, dynamic>;
          expect(point['x'], closeTo(centre.dx, 0.01));
          expect(point['y'], closeTo(centre.dy, 0.01));

          // The control is the 72x28 button inset 12px from the bottom-right.
          final Offset origin = tester.getTopLeft(boundary);
          final Map<String, dynamic> owner =
              outside['ownerRect'] as Map<String, dynamic>;
          expect(owner['left'], closeTo(origin.dx + 216, 0.01));
          expect(owner['top'], closeTo(origin.dy + 80, 0.01));
          expect(owner['width'], closeTo(72, 0.01));
          expect(owner['height'], closeTo(28, 0.01));
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'a plain button tapped at its own centre carries no tapPointOutsideOwner',
      (WidgetTester tester) async {
        _useSmallView(tester);
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _saveScreen(
              <Key, VoidCallback>{const ValueKey<String>('a'): () {}},
            ),
          );
          final String snapshot = (await duskSnapBuild())['snapshot'] as String;
          final String ref = _refsFor(snapshot, 'Save').single;

          final ServiceExtensionResponse response = await _pumpTap(tester, ref);

          final Map<String, dynamic> decoded =
              jsonDecode(response.result!) as Map<String, dynamic>;
          expect(decoded, contains('ref'));
          expect(decoded, isNot(contains('tapPointOutsideOwner')));
        } finally {
          handle.dispose();
        }
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

  // ---------------------------------------------------------------------------
  // Coordinate dispatch and reported points: what dusk:perf_run's semantics
  // pass records with the tree on and replays with it released.
  // ---------------------------------------------------------------------------

  group('coordinate dispatch', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(DuskPlugin.resetSemanticsForTesting);

    Future<ServiceExtensionResponse> settle(
      WidgetTester tester,
      Future<ServiceExtensionResponse> future,
    ) async {
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return future;
    }

    Future<void> host(WidgetTester tester, VoidCallback onTap) async {
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
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: const SizedBox(width: 200, height: 200),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
        'tap at x,y dispatches without a ref and reports the gate '
        'skipped', (WidgetTester tester) async {
      int taps = 0;
      await host(tester, () => taps++);

      final ServiceExtensionResponse response = await settle(
        tester,
        aiTestTapHandler('ext.dusk.tap', <String, String>{
          'x': '100',
          'y': '100',
        }),
      );

      expect(taps, 1);
      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['point'], <String, dynamic>{'x': 100.0, 'y': 100.0});
      final Map<String, dynamic> checks =
          decoded['checks'] as Map<String, dynamic>;
      expect(checks['gate'], 'skipped');
      expect(checks['semantics'], 'held');
      expect(decoded.containsKey('snapshot'), isFalse);
    });

    testWidgets('the checks block says released while the handle is held off',
        (WidgetTester tester) async {
      await host(tester, () {});
      DuskPlugin.acquireSemantics();
      DuskPlugin.releaseSemantics();

      final ServiceExtensionResponse response = await settle(
        tester,
        aiTestTapHandler('ext.dusk.tap', <String, String>{
          'x': '10',
          'y': '10',
        }),
      );

      final Map<String, dynamic> checks = (jsonDecode(response.result!)
          as Map<String, dynamic>)['checks'] as Map<String, dynamic>;
      expect(checks['semantics'], 'released');
    });

    testWidgets('a ref tap with reportPoint reports where it dispatched',
        (WidgetTester tester) async {
      await host(tester, () {});
      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(40, 60, 20, 20),
        element: tester.element(find.byType(Scaffold)),
        groupId: 'g',
        isTextField: false,
      );

      final ServiceExtensionResponse response = await settle(
        tester,
        aiTestTapHandler('ext.dusk.tap', <String, String>{
          'ref': ref,
          'reportPoint': 'true',
          'includeSnapshot': 'false',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
        }),
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['point'], isA<Map<String, dynamic>>());
      expect(decoded['ref'], ref);
    });

    testWidgets('a ref tap without reportPoint carries no point',
        (WidgetTester tester) async {
      await host(tester, () {});
      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(40, 60, 20, 20),
        element: tester.element(find.byType(Scaffold)),
        groupId: 'g',
        isTextField: false,
      );

      final ServiceExtensionResponse response = await settle(
        tester,
        aiTestTapHandler('ext.dusk.tap', <String, String>{
          'ref': ref,
          'includeSnapshot': 'false',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
        }),
      );

      expect(
        (jsonDecode(response.result!) as Map<String, dynamic>)
            .containsKey('point'),
        isFalse,
      );
    });

    testWidgets('hover with reportPoint reports where it hovered',
        (WidgetTester tester) async {
      await host(tester, () {});
      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(40, 60, 20, 20),
        element: tester.element(find.byType(Scaffold)),
        groupId: 'g',
        isTextField: false,
      );

      final ServiceExtensionResponse response = await settle(
        tester,
        aiTestHoverHandler('ext.dusk.hover', <String, String>{
          'ref': ref,
          'reportPoint': 'true',
          'includeSnapshot': 'false',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
        }),
      );

      expect(
        (jsonDecode(response.result!) as Map<String, dynamic>)['point'],
        isA<Map<String, dynamic>>(),
      );
    });

    testWidgets('drag from a ref by dx,dy reports both ends',
        (WidgetTester tester) async {
      await host(tester, () {});
      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(100, 100, 20, 20),
        element: tester.element(find.byType(Scaffold)),
        groupId: 'g',
        isTextField: false,
      );

      final ServiceExtensionResponse response = await settle(
        tester,
        aiTestDragHandler('ext.dusk.drag', <String, String>{
          'startRef': ref,
          'dx': '0',
          'dy': '-50',
          'reportPoint': 'true',
          'includeSnapshot': 'false',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
        }),
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      final Map<String, dynamic> from = decoded['from'] as Map<String, dynamic>;
      final Map<String, dynamic> to = decoded['to'] as Map<String, dynamic>;
      expect((to['y'] as num) - (from['y'] as num), -50);
      expect(to['x'], from['x']);
    });

    testWidgets('drag between coordinates needs no ref',
        (WidgetTester tester) async {
      await host(tester, () {});

      final ServiceExtensionResponse response = await settle(
        tester,
        aiTestDragHandler('ext.dusk.drag', <String, String>{
          'x': '100',
          'y': '150',
          'toX': '100',
          'toY': '50',
        }),
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['from'], <String, dynamic>{'x': 100.0, 'y': 150.0});
      expect(decoded['to'], <String, dynamic>{'x': 100.0, 'y': 50.0});
      expect((decoded['checks'] as Map<String, dynamic>)['gate'], 'skipped');
    });

    testWidgets('a tap with neither ref nor coordinates keeps the ref error',
        (WidgetTester tester) async {
      final ServiceExtensionResponse response = await aiTestTapHandler(
        'ext.dusk.tap',
        <String, String>{'x': '10'},
      );

      expect(response.errorDetail, contains('missing required param'));
      expect(response.errorDetail, contains('missing_param'));
    });
  });

  group('aiTestTapHandler snapshot mode', () {
    setUp(() {
      RefRegistry.resetForTesting();
      resetSnapshotBaselineForTesting();
    });
    tearDown(() {
      RefRegistry.resetForTesting();
      resetSnapshotBaselineForTesting();
    });

    Future<Map<String, dynamic>> tapCounter(
      WidgetTester tester,
      String ref,
      Map<String, String> extra,
    ) async {
      final Future<ServiceExtensionResponse> future = aiTestTapHandler(
        'ext.dusk.tap',
        <String, String>{
          'ref': ref,
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          ...extra,
        },
      );
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final ServiceExtensionResponse response = await future;
      return jsonDecode(response.result!) as Map<String, dynamic>;
    }

    Future<String> counterRef(WidgetTester tester) async {
      _useSmallView(tester);
      await tester.pumpWidget(MaterialApp(home: _Counter()));
      final String snapshot = (await duskSnapBuild())['snapshot'] as String;
      return _refsFor(snapshot, 'Counter: 0').single;
    }

    testWidgets('diff returns only the lines the tap changed',
        (WidgetTester tester) async {
      final String ref = await counterRef(tester);

      final Map<String, dynamic> decoded =
          await tapCounter(tester, ref, <String, String>{'snapshot': 'diff'});

      expect(decoded['snapshotMode'], 'diff');
      final List<String> lines = (decoded['snapshot'] as String).split('\n');
      expect(
        lines.take(2).toList(),
        <String>[
          '- - button "Counter: 0" [ref=$ref]',
          '+ - button "Counter: 1" [ref=$ref]',
        ],
      );
      expect(lines.length, 3);
      expect(lines.last, startsWith('(2 of '));
    });

    testWidgets('diff with no baseline yet returns the full snapshot',
        (WidgetTester tester) async {
      final String ref = await counterRef(tester);
      resetSnapshotBaselineForTesting();

      final Map<String, dynamic> decoded =
          await tapCounter(tester, ref, <String, String>{'snapshot': 'diff'});

      expect(decoded['snapshotMode'], 'diff');
      expect(decoded['snapshot'], contains('- button "Counter: 1" [ref=$ref]'));
      expect(decoded['snapshot'], isNot(contains('lines changed')));
    });

    testWidgets('none omits the snapshot key and overrides includeSnapshot',
        (WidgetTester tester) async {
      final String ref = await counterRef(tester);

      final Map<String, dynamic> decoded = await tapCounter(
        tester,
        ref,
        <String, String>{
          'snapshot': 'none',
          'includeSnapshot': 'true',
        },
      );

      expect(decoded.containsKey('snapshot'), isFalse);
      expect(decoded.containsKey('snapshotMode'), isFalse);
    });

    testWidgets('full overrides includeSnapshot false',
        (WidgetTester tester) async {
      final String ref = await counterRef(tester);

      final Map<String, dynamic> decoded = await tapCounter(
        tester,
        ref,
        <String, String>{
          'snapshot': 'full',
          'includeSnapshot': 'false',
        },
      );

      expect(decoded['snapshot'], contains('"Counter: 1" [ref=$ref]'));
      expect(decoded.containsKey('snapshotMode'), isFalse);
    });

    testWidgets('no snapshot param keeps the full text and adds no key',
        (WidgetTester tester) async {
      final String ref = await counterRef(tester);

      final Map<String, dynamic> decoded =
          await tapCounter(tester, ref, const <String, String>{});
      final String fresh = (await duskSnapBuild())['snapshot'] as String;

      expect(decoded['snapshot'], fresh);
      expect(decoded.containsKey('snapshotMode'), isFalse);
      expect(
        decoded.keys.toSet(),
        <String>{'ref', 'checks', 'effect', 'snapshot'}
            .intersection(decoded.keys.toSet()),
      );
    });
  });
}

/// A button whose label counts its own taps, the example app's Counter.
class _Counter extends StatefulWidget {
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => setState(() => _count++),
          child: Text('Counter: $_count'),
        ),
      ),
    );
  }
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
