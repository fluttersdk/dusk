import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_log_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DuskLogCapture', () {
    setUp(resetCapturedLogsForTesting);
    tearDown(resetCapturedLogsForTesting);

    // -------------------------------------------------------------------------
    // installLogCapture() / uninstallLogCapture()
    // -------------------------------------------------------------------------

    group('installLogCapture()', () {
      test('is idempotent — second call while installed is a no-op', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        final DebugPrintCallback afterFirst = debugPrint;
        installLogCapture(); // second call must not change the pointer
        expect(debugPrint, same(afterFirst));
      });

      test('captures a debugPrint call and stores it newest-first', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('hello from debugPrint');

        final List<Map<String, dynamic>> captured = recentCapturedLogs();
        expect(captured, hasLength(1));
        expect(captured.first['message'], equals('hello from debugPrint'));
        expect(captured.first['level'], equals('INFO'));
        expect(captured.first['logger'], equals('debugPrint'));
        expect(captured.first['time'], isA<String>());
      });

      test('chains the prior debugPrint handler', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        final List<String> priorReceived = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          priorReceived.add(message ?? '');
        };

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('chained message');

        expect(priorReceived, contains('chained message'));
        expect(
            recentCapturedLogs().first['message'], equals('chained message'));
      });

      test('stores entries newest-first', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('first');
        debugPrint('second');
        debugPrint('third');

        final List<Map<String, dynamic>> captured = recentCapturedLogs();
        expect(captured.first['message'], equals('third'));
        expect(captured.last['message'], equals('first'));
      });

      test('caps the buffer at 50 entries', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        for (int i = 0; i < 60; i++) {
          debugPrint('message $i');
        }

        final List<Map<String, dynamic>> all = recentCapturedLogs(limit: 100);
        expect(all, hasLength(50));
        // Newest-first: the last recorded (59) is at the head.
        expect(all.first['message'], equals('message 59'));
        expect(all.last['message'], equals('message 10'));
      });

      test('entry carries ISO8601 time field', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('timed message');

        final Map<String, dynamic> entry = recentCapturedLogs().first;
        final String time = entry['time'] as String;
        // ISO8601 UTC format: 2026-06-16T12:34:56.000Z
        expect(DateTime.tryParse(time), isNotNull);
        expect(time.endsWith('Z'), isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // uninstallLogCapture()
    // -------------------------------------------------------------------------

    group('uninstallLogCapture()', () {
      test('restores the prior debugPrint handler', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        final DebugPrintCallback afterInstall = debugPrint;
        expect(afterInstall, isNot(same(priorPrint)));

        uninstallLogCapture();
        expect(debugPrint, same(priorPrint));
      });

      test('is a no-op when not installed', () {
        // Must not throw.
        uninstallLogCapture();
      });

      test('re-captures the prior handler on each install/uninstall cycle', () {
        final DebugPrintCallback original = debugPrint;
        addTearDown(() => debugPrint = original);

        void firstPrior(String? msg, {int? wrapWidth}) {}
        debugPrint = firstPrior;
        installLogCapture();
        uninstallLogCapture();
        expect(debugPrint, same(firstPrior));

        void secondPrior(String? msg, {int? wrapWidth}) {}
        debugPrint = secondPrior;
        installLogCapture();
        uninstallLogCapture();
        expect(debugPrint, same(secondPrior));
      });
    });

    // -------------------------------------------------------------------------
    // recentCapturedLogs()
    // -------------------------------------------------------------------------

    group('recentCapturedLogs()', () {
      test('honors the limit argument', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        for (int i = 0; i < 10; i++) {
          debugPrint('msg $i');
        }

        expect(recentCapturedLogs(limit: 3), hasLength(3));
      });

      test('returns an empty list when nothing has been captured', () {
        expect(recentCapturedLogs(), isEmpty);
      });

      test('returns defensive copies — mutations do not affect the buffer', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('original');

        final List<Map<String, dynamic>> copy = recentCapturedLogs();
        copy.clear();

        expect(recentCapturedLogs(), hasLength(1));
      });
    });

    // -------------------------------------------------------------------------
    // recentCapturedLogs(minLevel)
    // -------------------------------------------------------------------------

    group('recentCapturedLogs() minLevel filter', () {
      test('null minLevel returns all entries', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('info one');
        debugPrint('info two');

        expect(recentCapturedLogs(), hasLength(2));
      });

      test('minLevel INFO includes debugPrint entries (level 800)', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('should pass INFO filter');

        final List<Map<String, dynamic>> result =
            recentCapturedLogs(minLevel: 'INFO');
        expect(result, hasLength(1));
      });

      test(
          'minLevel WARNING excludes debugPrint entries (level INFO < WARNING)',
          () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        addTearDown(uninstallLogCapture);

        debugPrint('below warning');

        final List<Map<String, dynamic>> result =
            recentCapturedLogs(minLevel: 'WARNING');
        expect(result, isEmpty);
      });
    });

    // -------------------------------------------------------------------------
    // resetCapturedLogsForTesting()
    // -------------------------------------------------------------------------

    group('resetCapturedLogsForTesting()', () {
      test('clears the buffer and uninstalls capture', () {
        final DebugPrintCallback priorPrint = debugPrint;
        addTearDown(() => debugPrint = priorPrint);

        installLogCapture();
        debugPrint('before reset');

        resetCapturedLogsForTesting();

        expect(recentCapturedLogs(), isEmpty);
        // After reset, a debugPrint no longer records into the capture buffer.
        debugPrint('after reset');
        expect(recentCapturedLogs(), isEmpty);
      });
    });
  });
}
