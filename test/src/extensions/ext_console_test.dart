import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_console.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext_console — recentLogsReader function-pointer indirection', () {
    setUp(() {
      // 1. Reset the reader to the default (empty list) before each test.
      recentLogsReader = ({int limit = 50, String? minLevel}) => const [];
    });

    // -------------------------------------------------------------------------
    // (a) Default reader returns empty list — missing-telescope graceful path.
    // -------------------------------------------------------------------------

    test(
      '(a) default reader returns empty list and count 0',
      () async {
        final response = await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['logs'], isA<List>());
        expect((decoded['logs'] as List).isEmpty, isTrue);
        expect(decoded['count'], equals(0));
      },
    );

    // -------------------------------------------------------------------------
    // (b) Custom reader wired — default limit 50 forwarded.
    // -------------------------------------------------------------------------

    test(
      '(b) wires through default limit=50 when no limit param supplied',
      () async {
        int? capturedLimit;
        String? capturedMinLevel;
        recentLogsReader = ({int limit = 50, String? minLevel}) {
          capturedLimit = limit;
          capturedMinLevel = minLevel;
          return const [];
        };

        await aiTestConsoleHandler('ext.dusk.console', <String, String>{});

        expect(capturedLimit, equals(50));
        expect(capturedMinLevel, isNull);
      },
    );

    // -------------------------------------------------------------------------
    // (c) Custom limit param is forwarded to the reader.
    // -------------------------------------------------------------------------

    test(
      '(c) custom limit param forwarded to reader',
      () async {
        int? capturedLimit;
        recentLogsReader = ({int limit = 50, String? minLevel}) {
          capturedLimit = limit;
          return const [];
        };

        await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{'limit': '10'},
        );

        expect(capturedLimit, equals(10));
      },
    );

    // -------------------------------------------------------------------------
    // (d) minLevel param is forwarded to the reader.
    // -------------------------------------------------------------------------

    test(
      '(d) minLevel param forwarded to reader',
      () async {
        String? capturedMinLevel;
        recentLogsReader = ({int limit = 50, String? minLevel}) {
          capturedMinLevel = minLevel;
          return const [];
        };

        await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{'minLevel': 'WARNING'},
        );

        expect(capturedMinLevel, equals('WARNING'));
      },
    );

    // -------------------------------------------------------------------------
    // (e) Reader returning logs — response carries logs + count.
    // -------------------------------------------------------------------------

    test(
      '(e) reader returning logs: response carries correct shape and count',
      () async {
        recentLogsReader = ({int limit = 50, String? minLevel}) => [
              {
                'level': 'INFO',
                'message': 'hello',
                'time': '2024-01-01T00:00:00.000Z',
                'logger': 'test.logger',
              },
              {
                'level': 'WARNING',
                'message': 'watch out',
                'time': '2024-01-01T00:01:00.000Z',
                'logger': 'test.logger',
              },
            ];

        final response = await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> logs = decoded['logs'] as List<dynamic>;
        expect(logs, hasLength(2));
        expect(decoded['count'], equals(2));
        expect((logs.first as Map<String, dynamic>)['level'], equals('INFO'));
        expect(
          (logs.first as Map<String, dynamic>)['message'],
          equals('hello'),
        );
      },
    );
  });

  group('ext_console — MCP descriptor presence', () {
    test('dusk_console MCP descriptor name is "dusk_console"', () {
      expect(kDuskConsoleMcpName, equals('dusk_console'));
    });

    test('dusk_console MCP descriptor extensionMethod is ext.dusk.console', () {
      expect(kDuskConsoleMcpExtension, equals('ext.dusk.console'));
    });
  });
}
