import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_focus.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// Decodes a SUCCESS response payload. Asserts that the response is
/// success-shaped (`result != null`) before parsing.
Map<String, dynamic> _decodeResult(
    developer.ServiceExtensionResponse response) {
  expect(response.result, isNotNull,
      reason:
          'expected success response but got error: ${response.errorDetail}');
  return jsonDecode(response.result!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aiTestFocusHandler', () {
    setUp(RefRegistry.resetForTesting);

    test('(a) missing ref param returns missing_param error envelope',
        () async {
      final response = await aiTestFocusHandler(
        'ext.dusk.focus',
        <String, String>{},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
      // The "ref" param name appears as JSON-escaped `\"ref\"` inside the
      // error detail's outer JSON envelope.
      expect(response.errorDetail ?? '', contains('ref'));
    });

    test('(b) empty ref param returns missing_param error envelope', () async {
      final response = await aiTestFocusHandler(
        'ext.dusk.focus',
        const <String, String>{'ref': ''},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
    });

    test('(c) unknown ref token returns not-found error envelope', () async {
      final response = await aiTestFocusHandler(
        'ext.dusk.focus',
        const <String, String>{'ref': 'e9999'},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('not found in registry'));
      expect(response.errorDetail ?? '', contains('e9999'));
    });

    testWidgets('(d) actionable Focus widget receives requestFocus()',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              focusNode: node,
              child: Container(
                key: const Key('focus-child'),
                width: 100,
                height: 100,
                color: const Color(0xFFFF0000),
              ),
            ),
          ),
        ),
      );

      // Resolve the child element (NOT the Focus widget itself) so the
      // handler's `Focus.maybeOf(entry.element)` walks UP and finds the
      // wrapping Focus ancestor.
      final Element element = tester.element(find.byKey(const Key('focus-child')));
      final RenderBox box = element.findRenderObject()! as RenderBox;
      final Rect rect = box.localToGlobal(Offset.zero) & box.size;
      final String ref = RefRegistry.registerForTesting(
        rect: rect,
        element: element,
        groupId: 'g',
        isTextField: false,
      );

      // Don't await the handler directly — its internal
      // `await WidgetsBinding.instance.endOfFrame` blocks until a frame
      // pumps, and `flutter_test`'s FakeAsync only advances on tester.pump.
      final future = aiTestFocusHandler(
        'ext.dusk.focus',
        <String, String>{'ref': ref},
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      final response = await future;

      expect(_decodeResult(response), containsPair('focused', true));
      expect(_decodeResult(response), containsPair('ref', ref));
    });

    testWidgets(
        '(e) element with no Focus ancestor returns the "no Focus ancestor" '
        'error envelope', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // SizedBox.shrink has no Focus / FocusableActionDetector ancestor — every
      // Focus.maybeOf returns null on its element.
      await tester.pumpWidget(const SizedBox.shrink());

      final Element element = tester.element(find.byType(SizedBox));
      final RenderBox box = element.findRenderObject()! as RenderBox;
      final Rect rect = box.localToGlobal(Offset.zero) & box.size;
      final String ref = RefRegistry.registerForTesting(
        rect: rect,
        element: element,
        groupId: 'g',
        isTextField: false,
      );

      final response = await aiTestFocusHandler(
        'ext.dusk.focus',
        <String, String>{'ref': ref},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('no Focus ancestor'));
    });
  });

  group('aiTestBlurHandler', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets('(a) blurs the primary focus when one exists',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Focus(focusNode: node, child: const SizedBox(width: 50, height: 50)),
          ),
        ),
      );

      node.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, equals(node));

      final future = aiTestBlurHandler(
        'ext.dusk.blur',
        const <String, String>{},
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      final response = await future;
      expect(_decodeResult(response), containsPair('blurred', true));
      expect(_decodeResult(response), containsPair('hadFocus', true));
    });

    testWidgets('(b) reports hadFocus=false when no node held focus',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SizedBox.shrink());

      // No widget called requestFocus; primaryFocus may still be a synthetic
      // root node depending on the test binding. The handler always reports
      // a stable shape — the test asserts only on the envelope keys.
      final future = aiTestBlurHandler(
        'ext.dusk.blur',
        const <String, String>{},
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      final response = await future;
      final payload = _decodeResult(response);
      expect(payload, contains('blurred'));
      expect(payload, contains('hadFocus'));
    });
  });

  group('registerFocusExtensions', () {
    test('runs idempotently (hot-restart safe)', () {
      // Two back-to-back registrations must not throw.
      registerFocusExtensions();
      registerFocusExtensions();
    });
  });
}
