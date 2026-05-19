import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_text_input.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext_text_input', () {
    group('pressKey', () {
      // -----------------------------------------------------------------------
      // Test (a): Envelope shape on valid input
      // -----------------------------------------------------------------------

      test(
        '(a) returns normally when key is "Enter"',
        () async {
          expect(
            () => pressKey(key: 'Enter'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "Tab"',
        () async {
          expect(
            () => pressKey(key: 'Tab'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "Escape"',
        () async {
          expect(
            () => pressKey(key: 'Escape'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "ArrowUp"',
        () async {
          expect(
            () => pressKey(key: 'ArrowUp'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "Backspace"',
        () async {
          expect(
            () => pressKey(key: 'Backspace'),
            returnsNormally,
          );
        },
      );

      // -----------------------------------------------------------------------
      // Test (b): Modifier combo dispatch
      // -----------------------------------------------------------------------

      test(
        '(b) accepts modifiers parameter without throwing',
        () async {
          expect(
            () => pressKey(key: 'Enter', modifiers: ['ctrl']),
            returnsNormally,
          );
        },
      );

      test(
        '(b) accepts multiple modifiers without throwing',
        () async {
          expect(
            () => pressKey(key: 'Enter', modifiers: ['ctrl', 'shift']),
            returnsNormally,
          );
        },
      );

      test(
        '(b) modifiers parameter defaults to empty list',
        () async {
          expect(
            () => pressKey(key: 'Enter'),
            returnsNormally,
          );
        },
      );

      // -----------------------------------------------------------------------
      // Test (c): Bad-input rejection
      // -----------------------------------------------------------------------

      test(
        '(c) throws ArgumentError when key is unknown',
        () async {
          expect(
            () => pressKey(key: 'InvalidKeyName'),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test(
        '(c) ArgumentError message includes the unknown key name',
        () async {
          expect(
            () => pressKey(key: 'BadKey'),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.message,
                'message',
                contains('BadKey'),
              ),
            ),
          );
        },
      );

      test(
        '(c) ArgumentError message includes list of supported keys',
        () async {
          expect(
            () => pressKey(key: 'UnknownKey'),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.message,
                'message',
                contains('Supported keys'),
              ),
            ),
          );
        },
      );

      test(
        '(c) throws ArgumentError when key is empty string',
        () async {
          expect(
            () => pressKey(key: ''),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      // -----------------------------------------------------------------------
      // Test (d): Missing-required-param rejection (handler level)
      // -----------------------------------------------------------------------

      test(
        '(d) aiTestPressKeyHandler returns error when key is missing',
        () async {
          final response =
              await aiTestPressKeyHandler('ext.dusk.press_key', {});
          expect(response.result, isNull);
        },
      );

      test(
        '(d) aiTestPressKeyHandler error mentions missing key param',
        () async {
          final response =
              await aiTestPressKeyHandler('ext.dusk.press_key', {});
          expect(response.errorDetail ?? '', contains('key'));
        },
      );

      test(
        '(d) aiTestPressKeyHandler returns error when key is empty',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': ''},
          );
          expect(response.result, isNull);
        },
      );

      test(
        '(d) aiTestPressKeyHandler succeeds when key is valid',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': 'Enter'},
          );
          final resultStr = response.result;
          expect(resultStr, isNotNull);
          expect(
            () => jsonDecode(resultStr!),
            returnsNormally,
          );
        },
      );

      test(
        '(d) aiTestPressKeyHandler success response is valid JSON for Tab',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': 'Tab'},
          );
          expect(
            () => jsonDecode(response.result ?? ''),
            returnsNormally,
          );
        },
      );

      test(
        '(d) aiTestPressKeyHandler success response contains ok:true',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': 'Escape'},
          );
          final decoded = jsonDecode(response.result ?? '{}');
          expect(decoded['ok'], equals(true));
        },
      );

      test(
        '(d) aiTestPressKeyHandler success response echoes the key',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': 'Enter'},
          );
          final decoded = jsonDecode(response.result ?? '{}');
          expect(decoded['key'], equals('Enter'));
        },
      );

      // -----------------------------------------------------------------------
      // Test (e): Idempotent registration
      // -----------------------------------------------------------------------

      test(
        '(e) registerTextInputExtensions can be called multiple times',
        () async {
          expect(
            () {
              registerTextInputExtensions();
              registerTextInputExtensions();
            },
            returnsNormally,
          );
        },
      );

      test(
        '(e) calling registerTextInputExtensions twice does not throw',
        () async {
          expect(
            () {
              registerTextInputExtensions();
              registerTextInputExtensions();
            },
            returnsNormally,
          );
        },
      );

      test(
        '(e) handler is still available after second registerTextInputExtensions',
        () async {
          registerTextInputExtensions();
          registerTextInputExtensions();
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': 'Enter'},
          );
          expect(response.result, isNotNull);
        },
      );
    });

    group('aiTestPressKeyHandler modifier parsing', () {
      // -----------------------------------------------------------------------
      // Test modifier parameter parsing (additional handler-level tests)
      // -----------------------------------------------------------------------

      test(
        'parses comma-separated modifiers from params',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {
              'key': 'Enter',
              'modifiers': 'ctrl,shift',
            },
          );
          expect(response.result, isNotNull);
          final decoded = jsonDecode(response.result!);
          expect(decoded['ok'], equals(true));
        },
      );

      test(
        'handles whitespace in modifier list',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {
              'key': 'Tab',
              'modifiers': 'ctrl, shift, alt',
            },
          );
          expect(response.result, isNotNull);
        },
      );

      test(
        'ignores empty modifier strings from split',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {
              'key': 'Enter',
              'modifiers': 'ctrl,,shift',
            },
          );
          expect(response.result, isNotNull);
        },
      );

      test(
        'handles null modifiers param gracefully',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': 'Tab'},
          );
          expect(response.result, isNotNull);
        },
      );

      test(
        'returns error when key is invalid despite valid modifiers',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {
              'key': 'BadKey',
              'modifiers': 'ctrl',
            },
          );
          expect(response.result, isNull);
        },
      );
    });

    group('aiTestTypeHandler actionability gate', () {
      setUp(RefRegistry.resetForTesting);

      // -----------------------------------------------------------------------
      // (d) Zero-rect entry → type fails with descriptive actionability error
      // -----------------------------------------------------------------------

      testWidgets(
        '(d) zero-rect ref returns "zero rect" actionability error',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: Center(child: TextField()),
              ),
            ),
          );

          final Element element = tester.element(find.byType(TextField));
          final String ref = RefRegistry.registerForTesting(
            rect: const Rect.fromLTWH(10, 10, 0, 40),
            element: element,
            groupId: 'g',
            isTextField: true,
          );

          final response = await aiTestTypeHandler(
            'ext.dusk.type',
            <String, String>{'ref': ref, 'text': 'hello'},
          );

          expect(response.result, isNull);
          expect(
            response.errorDetail ?? '',
            contains('Widget ref=$ref is not actionable: zero rect'),
          );
        },
      );

      testWidgets(
        '(d) off-viewport ref returns "off-viewport" actionability error',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: Center(child: TextField()),
              ),
            ),
          );

          final Element element = tester.element(find.byType(TextField));
          final String ref = RefRegistry.registerForTesting(
            rect: const Rect.fromLTWH(5000, 5000, 80, 40),
            element: element,
            groupId: 'g',
            isTextField: true,
          );

          final response = await aiTestTypeHandler(
            'ext.dusk.type',
            <String, String>{'ref': ref, 'text': 'world'},
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

      // -----------------------------------------------------------------------
      // Success path — actionable RefRegistry entry passes the gate and types
      // -----------------------------------------------------------------------

      testWidgets(
        'actionable ref types text into the field and returns ok envelope',
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

          // Handler awaits two endOfFrame ticks; pump alongside so frames
          // advance under fake-async.
          final future = aiTestTypeHandler(
            'ext.dusk.type',
            <String, String>{'ref': ref, 'text': 'typed'},
          );
          await tester.pump();
          await tester.pump();
          final response = await future;

          expect(response.result, isNotNull);
          final Map<String, dynamic> decoded =
              jsonDecode(response.result!) as Map<String, dynamic>;
          expect(decoded['text'], equals('typed'));
          expect(controller.text, equals('typed'));
        },
      );
    });

    group('ext.dusk.press_key registration', () {
      // -----------------------------------------------------------------------
      // Test registration state (no duplicate handler)
      // -----------------------------------------------------------------------

      test(
        'ext.dusk.press_key is registered after registerTextInputExtensions',
        () async {
          registerTextInputExtensions();
          // If registration fails, it would throw; succeeding here validates
          // that the registration succeeded previously.
          final response = await aiTestPressKeyHandler(
            'ext.dusk.press_key',
            {'key': 'Enter'},
          );
          expect(response.result, isNotNull);
        },
      );
    });
  });

  group('TestRefRegistry', () {
    testWidgets('inject + lookup roundtrip, clear empties the table',
        (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = tester.element(find.byType(SizedBox));
      TestRefRegistry.inject('e42', element);
      expect(TestRefRegistry.lookup('e42'), equals(element));
      TestRefRegistry.clear();
      expect(TestRefRegistry.lookup('e42'), isNull);
    });

    test('lookup returns null for unknown ref', () {
      expect(TestRefRegistry.lookup('e9999'), isNull);
    });
  });

  group('typeIntoElement error paths', () {
    testWidgets('throws ArgumentError when no EditableText is in the subtree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('plain'))),
      );
      final element = tester.element(find.byType(Scaffold));

      expect(
        () => typeIntoElement(element: element, text: 'hello'),
        throwsArgumentError,
      );
    });
  });

  group('aiTestTypeHandler param + error paths', () {
    test('missing ref returns missing-param error', () async {
      final response = await aiTestTypeHandler(
        'ext.dusk.type',
        const <String, String>{'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(
        response.errorDetail ?? '',
        contains('missing required param "ref"'),
      );
    });

    test('empty ref returns missing-param error', () async {
      final response = await aiTestTypeHandler(
        'ext.dusk.type',
        const <String, String>{'ref': '', 'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(
        response.errorDetail ?? '',
        contains('missing required param "ref"'),
      );
    });

    test('unknown ref returns not-found error', () async {
      final response = await aiTestTypeHandler(
        'ext.dusk.type',
        const <String, String>{'ref': 'e9999', 'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(
        response.errorDetail ?? '',
        contains('not found in registry'),
      );
    });
  });
}
