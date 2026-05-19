import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext_exceptions — recentExceptionsReader function-pointer indirection',
      () {
    setUp(() {
      // 1. Reset the reader to the default (empty list) before each test.
      recentExceptionsReader = ({int limit = 20}) => const [];
    });

    // -------------------------------------------------------------------------
    // (a) Default reader returns empty list — missing-telescope graceful path.
    // -------------------------------------------------------------------------

    test(
      '(a) default reader returns empty list and count 0',
      () async {
        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['exceptions'], isA<List>());
        expect((decoded['exceptions'] as List).isEmpty, isTrue);
        expect(decoded['count'], equals(0));
      },
    );

    // -------------------------------------------------------------------------
    // (b) Custom limit param forwarded to the reader.
    // -------------------------------------------------------------------------

    test(
      '(b) custom limit param forwarded to reader',
      () async {
        int? capturedLimit;
        recentExceptionsReader = ({int limit = 20}) {
          capturedLimit = limit;
          return const [];
        };

        await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{'limit': '5'},
        );

        expect(capturedLimit, equals(5));
      },
    );

    // -------------------------------------------------------------------------
    // (c) Missing-telescope graceful — null reader pointer stays as default.
    // -------------------------------------------------------------------------

    test(
      '(c) missing-telescope graceful: default reader returns empty list',
      () async {
        // Default state: recentExceptionsReader = () => const []
        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{'limit': '10'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['count'], equals(0));
      },
    );

    // -------------------------------------------------------------------------
    // (d) Reader returning exceptions — response carries correct shape.
    // -------------------------------------------------------------------------

    test(
      '(d) reader returning exceptions: response carries correct shape',
      () async {
        recentExceptionsReader = ({int limit = 20}) => [
              {
                'type': 'ArgumentError',
                'message': 'bad arg',
                'stackHead': 'at foo()\nat bar()\nat baz()',
                'time': '2024-01-01T00:00:00.000Z',
              },
            ];

        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> exceptions = decoded['exceptions'] as List<dynamic>;
        expect(exceptions, hasLength(1));
        expect(decoded['count'], equals(1));
        expect(
          (exceptions.first as Map<String, dynamic>)['type'],
          equals('ArgumentError'),
        );
        expect(
          (exceptions.first as Map<String, dynamic>)['message'],
          equals('bad arg'),
        );
      },
    );
  });

  group('ext_exceptions — MCP descriptor presence', () {
    test('dusk_exceptions MCP descriptor name is "dusk_exceptions"', () {
      expect(kDuskExceptionsMcpName, equals('dusk_exceptions'));
    });

    test(
      'dusk_exceptions MCP descriptor extensionMethod is ext.dusk.exceptions',
      () {
        expect(
          kDuskExceptionsMcpExtension,
          equals('ext.dusk.exceptions'),
        );
      },
    );
  });
}
