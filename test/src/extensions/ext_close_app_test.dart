import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_close_app.dart';
import 'package:fluttersdk_dusk/src/utils/error_envelope.dart';

void main() {
  // Reset the injection point before every test so tests are isolated.
  setUp(() {
    closeAppImpl = defaultCloseApp;
  });

  group('ext.dusk.close_app', () {
    // -------------------------------------------------------------------------
    // (a) Envelope shape
    // -------------------------------------------------------------------------

    test(
      '(a) handler returns {"closed": true} and confirms stub was invoked',
      () async {
        bool closeCalled = false;
        closeAppImpl = () async {
          closeCalled = true;
        };

        final response = await extDuskCloseAppHandler(
          'ext.dusk.close_app',
          <String, String>{},
        );

        // A success response has a non-null result and a null errorCode.
        expect(
          response.result,
          isNotNull,
          reason: 'success response must carry a result body',
        );
        expect(
          response.errorCode,
          isNull,
          reason: 'success response must not carry an errorCode',
        );

        final Map<String, dynamic> result =
            jsonDecode(response.result!) as Map<String, dynamic>;

        expect(
          result['closed'],
          isTrue,
          reason: 'envelope must carry closed: true',
        );

        expect(closeCalled, isTrue, reason: 'closeAppImpl stub was invoked');
      },
    );

    test(
      '(a) response body is valid JSON with the closed key set to true',
      () async {
        closeAppImpl = () async {};

        final response = await extDuskCloseAppHandler(
          'ext.dusk.close_app',
          <String, String>{},
        );

        final Map<String, dynamic> result =
            jsonDecode(response.result!) as Map<String, dynamic>;

        expect(
          result.containsKey('closed'),
          isTrue,
          reason: 'response body must have the closed key',
        );
        expect(
          result['closed'],
          isTrue,
        );
      },
    );

    // -------------------------------------------------------------------------
    // (b) Injection point is honored (real system close not fired in tests)
    // -------------------------------------------------------------------------

    test(
      '(b) does not call real system close when injection point is overridden',
      () async {
        bool stubInvoked = false;

        closeAppImpl = () async {
          // Stub records the call but does not pop the real navigator.
          stubInvoked = true;
        };

        await extDuskCloseAppHandler(
          'ext.dusk.close_app',
          <String, String>{},
        );

        expect(
          stubInvoked,
          isTrue,
          reason: 'injection point stub must be called instead of real close',
        );
      },
    );

    // -------------------------------------------------------------------------
    // (c) Idempotent registration
    // -------------------------------------------------------------------------

    test(
      '(c) registerCloseAppExtension can be called multiple times without throw',
      () {
        expect(
          () {
            registerCloseAppExtension();
            registerCloseAppExtension();
          },
          returnsNormally,
        );
      },
    );

    test(
      '(c) handler is still callable after double registration',
      () async {
        closeAppImpl = () async {};

        registerCloseAppExtension();
        registerCloseAppExtension();

        final response = await extDuskCloseAppHandler(
          'ext.dusk.close_app',
          <String, String>{},
        );

        expect(
          response.errorCode,
          isNull,
          reason: 'double registration must not break the handler',
        );
        expect(response.result, isNotNull);
      },
    );

    // -------------------------------------------------------------------------
    // (d) Extra / ignored params do not break the handler
    // -------------------------------------------------------------------------

    test(
      '(d) handler ignores unknown params and still returns closed: true',
      () async {
        closeAppImpl = () async {};

        final response = await extDuskCloseAppHandler(
          'ext.dusk.close_app',
          <String, String>{'unexpected': 'value'},
        );

        final Map<String, dynamic> result =
            jsonDecode(response.result!) as Map<String, dynamic>;

        expect(result['closed'], isTrue);
      },
    );

    test(
      '(e) handler returns error envelope when closeAppImpl throws',
      () async {
        closeAppImpl = () async {
          throw Exception('boom');
        };

        final response = await extDuskCloseAppHandler(
          'ext.dusk.close_app',
          <String, String>{},
        );

        expect(response.errorCode, isNotNull);
        // Step 3.3: error envelope contract — message carries the raw
        // exception text; envelope.type is 'unexpected' for caught throws.
        expect(
          parseMessageFromErrorDetail(response.errorDetail ?? ''),
          contains('boom'),
        );
        final Map<String, dynamic>? envelope =
            parseEnvelopeFromErrorDetail(response.errorDetail ?? '');
        expect(envelope, isNotNull);
        expect(envelope!['type'], equals('unexpected'));
      },
    );
  });
}
