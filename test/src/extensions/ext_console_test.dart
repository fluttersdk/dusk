import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_log_capture.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_console.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext_console — recentLogsReader function-pointer indirection', () {
    setUp(() {
      // Reset the reader to the default (empty list) and clear the in-package
      // buffer so tests start from a known state.
      recentLogsReader = ({int limit = 50, String? minLevel}) => const [];
      resetCapturedLogsForTesting();
    });

    tearDown(resetCapturedLogsForTesting);

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

  // ---------------------------------------------------------------------------
  // In-package buffer — telescope ABSENT path (the D5 core scenario)
  // ---------------------------------------------------------------------------

  group('ext_console — in-package capture (telescope absent)', () {
    setUp(() {
      // Keep telescope reader empty so it cannot pollute assertions.
      recentLogsReader = ({int limit = 50, String? minLevel}) => const [];
      resetCapturedLogsForTesting();
    });

    tearDown(resetCapturedLogsForTesting);

    test(
      '(f) debugPrint after installLogCapture() appears in the console reader',
      () async {
        final DebugPrintCallback prior = debugPrint;
        addTearDown(() => debugPrint = prior);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('captured without telescope');

        final response = await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> logs = decoded['logs'] as List<dynamic>;
        expect(logs, isNotEmpty);
        expect(
          (logs.first as Map<String, dynamic>)['message'],
          equals('captured without telescope'),
        );
        expect(decoded['count'], greaterThan(0));
      },
    );

    test(
      '(g) minLevel WARNING excludes in-package INFO entries',
      () async {
        final DebugPrintCallback prior = debugPrint;
        addTearDown(() => debugPrint = prior);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('info level message');

        final response = await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{'minLevel': 'WARNING'},
        );

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> logs = decoded['logs'] as List<dynamic>;
        expect(logs, isEmpty);
        expect(decoded['count'], equals(0));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Merge + dedup — telescope PRESENT path
  // ---------------------------------------------------------------------------

  group('ext_console — merge+dedup (telescope present)', () {
    setUp(() {
      resetCapturedLogsForTesting();
    });

    tearDown(resetCapturedLogsForTesting);

    test(
      '(h) dedupes entries present in both in-package buffer and telescope reader',
      () async {
        final DebugPrintCallback prior = debugPrint;
        addTearDown(() => debugPrint = prior);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        // Record the same message via debugPrint (goes into in-package buffer).
        debugPrint('shared message');

        // Telescope reader returns the same entry (same level+message+logger).
        recentLogsReader = ({int limit = 50, String? minLevel}) => [
              <String, dynamic>{
                'level': 'INFO',
                'message': 'shared message',
                'logger': 'debugPrint',
                'time': '2024-01-01T00:00:00.000Z',
              },
            ];

        final response = await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{},
        );

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> logs = decoded['logs'] as List<dynamic>;
        // Must appear only once despite both sources containing it.
        expect(
            logs.where((dynamic e) {
              return (e as Map<String, dynamic>)['message'] == 'shared message';
            }).length,
            equals(1));
      },
    );

    test(
      '(i) non-duplicate telescope entries are included in the response',
      () async {
        final DebugPrintCallback prior = debugPrint;
        addTearDown(() => debugPrint = prior);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('from debugPrint');

        // Telescope contributes a distinct entry.
        recentLogsReader = ({int limit = 50, String? minLevel}) => [
              <String, dynamic>{
                'level': 'WARNING',
                'message': 'from telescope',
                'logger': 'my.logger',
                'time': '2024-01-01T00:00:00.000Z',
              },
            ];

        final response = await aiTestConsoleHandler(
          'ext.dusk.console',
          <String, String>{},
        );

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> logs = decoded['logs'] as List<dynamic>;
        expect(logs, hasLength(2));
        // In-package entry comes first (newest-first, buffered before telescope).
        expect(
          (logs.first as Map<String, dynamic>)['message'],
          equals('from debugPrint'),
        );
        expect(
          (logs.last as Map<String, dynamic>)['message'],
          equals('from telescope'),
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
