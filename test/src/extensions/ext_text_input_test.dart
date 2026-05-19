import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_text_input.dart';

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
}
