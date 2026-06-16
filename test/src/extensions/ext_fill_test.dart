import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_fill.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aiTestFillHandler', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'focus + clear + type into a TextField in one call returns the typed text',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller =
            TextEditingController(text: 'old value');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );

        final Element element = tester.element(find.byType(TextField));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: element,
          groupId: 'g',
          isTextField: true,
        );

        // The handler chains focus + clear + type, each awaiting one or two
        // endOfFrame ticks; pump alongside so frames advance under fake-async.
        // checkStable / checkReceivesEvents opt-out: the synthetic rect does
        // not align with the live TextField geometry.
        final future = aiTestFillHandler(
          'ext.dusk.fill',
          <String, String>{
            'ref': ref,
            'text': 'fresh text',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> json =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(json['ref'], equals(ref));
        expect(json['text'], equals('fresh text'));
        expect(json['filled'], isTrue);
        expect(controller.text, equals('fresh text'));
      },
    );

    testWidgets(
      'missing ref returns a missing-param error',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        final response = await aiTestFillHandler(
          'ext.dusk.fill',
          const <String, String>{'text': 'hello'},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
      },
    );

    testWidgets(
      'unknown ref returns a not-found error',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        final response = await aiTestFillHandler(
          'ext.dusk.fill',
          const <String, String>{'ref': 'e999', 'text': 'hello'},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('not found in registry'));
      },
    );

    testWidgets(
      'resolves a q-handle against the live tree and fills it',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TextField(
                  key: const ValueKey<String>('fill-field'),
                  controller: controller,
                ),
              ),
            ),
          ),
        );

        final String ref = RefRegistry.registerQuery(
          const DuskQuery(keyValue: 'fill-field'),
        );

        final future = aiTestFillHandler(
          'ext.dusk.fill',
          <String, String>{
            'ref': ref,
            'text': 'retry value',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> json =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(json['text'], equals('retry value'));
        expect(controller.text, equals('retry value'));
      },
    );

    testWidgets(
      'a permanently stale q-handle surfaces a stale error after the retry',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));

        // No matching widget exists, so both the first attempt and the retry
        // fail to resolve the handle.
        final String ref = RefRegistry.registerQuery(
          const DuskQuery(keyValue: 'never-matches'),
        );

        final response = await aiTestFillHandler(
          'ext.dusk.fill',
          <String, String>{
            'ref': ref,
            'text': 'whatever',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('"type":"stale"'));
      },
    );
  });

  group('registerFillExtension', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerFillExtension();
      registerFillExtension();
    });
  });
}
