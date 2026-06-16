import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_error_capture.dart';
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

  group('ext_exceptions — in-package buffer merge', () {
    setUp(() {
      // 1. Reset reader to the default (empty list) before each test.
      recentExceptionsReader = ({int limit = 20}) => const [];
      // 2. Reset in-package buffer so no captured errors leak from prior tests.
      resetCapturedExceptionsForTesting();
    });

    tearDown(() {
      // Ensure the buffer and capture hook are clean after each test.
      resetCapturedExceptionsForTesting();
    });

    // -------------------------------------------------------------------------
    // (e) In-package buffer populated, telescope reader empty — entry surfaces.
    // -------------------------------------------------------------------------

    test(
      '(e) in-package buffer entry surfaces when telescope reader is empty',
      () async {
        // Seed the buffer directly via installErrorCapture + synthetic error.
        installErrorCapture();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError('test overflow error'),
            stack: StackTrace.fromString('at a()\nat b()\nat c()'),
            library: 'test library',
          ),
        );

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
          (exceptions.first as Map<String, dynamic>)['message'],
          contains('test overflow error'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // (f) Both sources populated — merged set is returned, largest count wins.
    // -------------------------------------------------------------------------

    test(
      '(f) both sources populated: merged union is returned',
      () async {
        // Telescope reader returns one entry.
        recentExceptionsReader = ({int limit = 20}) => [
              {
                'type': 'ArgumentError',
                'message': 'telescope error',
                'stackHead': 'at x()',
                'library': null,
                'fatal': false,
                'time': '2024-01-01T00:00:00.000Z',
              },
            ];

        // In-package buffer has a different entry.
        installErrorCapture();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError('captured error'),
            stack: StackTrace.fromString('at a()\nat b()\nat c()'),
            library: 'test library',
          ),
        );

        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> exceptions = decoded['exceptions'] as List<dynamic>;
        expect(decoded['count'], equals(2));
        final List<String> messages = exceptions
            .map(
                (dynamic e) => (e as Map<String, dynamic>)['message'] as String)
            .toList();
        expect(messages, contains('telescope error'));
        expect(
            messages.any((String m) => m.contains('captured error')), isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (g) Duplicate entry (same type, message, stackHead) deduped to one.
    // -------------------------------------------------------------------------

    test(
      '(g) duplicate entry in both sources is deduped to one',
      () async {
        // 1. Populate the in-package buffer with a known error.
        installErrorCapture();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: ArgumentError('duplicate msg'),
            stack: StackTrace.fromString('at foo()'),
            library: 'test library',
          ),
        );

        // 2. Read back exactly what the buffer captured so the telescope entry
        //    can be constructed with identical (type, message, stackHead).
        final List<Map<String, dynamic>> buffered =
            recentCapturedExceptions(limit: 1);
        expect(buffered, hasLength(1));
        final Map<String, dynamic> captured = buffered.first;

        // 3. Wire the telescope reader to return the same entry shape.
        recentExceptionsReader = ({int limit = 20}) => [
              {
                'type': captured['type'],
                'message': captured['message'],
                'stackHead': captured['stackHead'],
                'library': captured['library'],
                'fatal': captured['fatal'],
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
        expect(decoded['count'], equals(1));
      },
    );

    // -------------------------------------------------------------------------
    // (h) Limit applied to the merged set, not per-source.
    // -------------------------------------------------------------------------

    test(
      '(h) limit applied to merged union, not per-source',
      () async {
        // Telescope reader returns 3 entries.
        recentExceptionsReader =
            ({int limit = 20}) => List<Map<String, dynamic>>.generate(
                  3,
                  (int i) => <String, dynamic>{
                    'type': 'Error',
                    'message': 'telescope-$i',
                    'stackHead': 'at t$i()',
                    'library': null,
                    'fatal': false,
                    'time': '2024-01-01T00:00:0$i.000Z',
                  },
                );

        // In-package buffer has 3 additional distinct entries.
        installErrorCapture();
        for (int i = 0; i < 3; i++) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: StateError('captured-$i'),
              stack: StackTrace.fromString('at c$i()'),
              library: 'test library',
            ),
          );
        }

        // Request only 4 from the merged set of 6.
        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{'limit': '4'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['count'], equals(4));
        expect((decoded['exceptions'] as List).length, equals(4));
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

  group('ext_exceptions — since filter', () {
    setUp(() {
      // 1. Reset reader and buffer before each test.
      recentExceptionsReader = ({int limit = 20}) => const [];
      resetCapturedExceptionsForTesting();
    });

    tearDown(() {
      resetCapturedExceptionsForTesting();
    });

    // -------------------------------------------------------------------------
    // (i) Two exceptions at different timestamps split correctly by since.
    // -------------------------------------------------------------------------

    test(
      '(i) since filter: only exceptions strictly after since are returned',
      () async {
        // Seed two entries with distinct timestamps via the telescope reader.
        recentExceptionsReader = ({int limit = 20}) => [
              {
                'type': 'StateError',
                'message': 'early error',
                'stackHead': 'at early()',
                'library': 'test',
                'fatal': false,
                'time': '2024-01-01T10:00:00.000Z',
              },
              {
                'type': 'StateError',
                'message': 'late error',
                'stackHead': 'at late()',
                'library': 'test',
                'fatal': false,
                'time': '2024-01-01T12:00:00.000Z',
              },
            ];

        // since = 11:00 — only 'late error' (12:00) is strictly after.
        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{'since': '2024-01-01T11:00:00.000Z'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> exceptions = decoded['exceptions'] as List<dynamic>;
        expect(decoded['count'], equals(1));
        expect(exceptions, hasLength(1));
        expect(
          (exceptions.first as Map<String, dynamic>)['message'],
          equals('late error'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // (j) No since param returns the full cumulative list (backward compatible).
    // -------------------------------------------------------------------------

    test(
      '(j) no since param: cumulative list returned with identical payload keys',
      () async {
        recentExceptionsReader = ({int limit = 20}) => [
              {
                'type': 'ArgumentError',
                'message': 'first error',
                'stackHead': 'at a()',
                'library': 'lib',
                'fatal': false,
                'time': '2024-06-01T09:00:00.000Z',
              },
              {
                'type': 'StateError',
                'message': 'second error',
                'stackHead': 'at b()',
                'library': 'lib',
                'fatal': false,
                'time': '2024-06-01T10:00:00.000Z',
              },
            ];

        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;

        // Both entries present.
        expect(decoded['count'], equals(2));
        expect((decoded['exceptions'] as List).length, equals(2));

        // Payload keys/shape: type, message, stackHead, library, fatal, time.
        final Map<String, dynamic> first =
            (decoded['exceptions'] as List)[0] as Map<String, dynamic>;
        expect(first.containsKey('type'), isTrue);
        expect(first.containsKey('message'), isTrue);
        expect(first.containsKey('stackHead'), isTrue);
        expect(first.containsKey('library'), isTrue);
        expect(first.containsKey('fatal'), isTrue);
        expect(first.containsKey('time'), isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (k) since exactly equal to entry time excludes that entry (strictly after).
    // -------------------------------------------------------------------------

    test(
      '(k) since equal to entry time: entry is excluded (strictly after only)',
      () async {
        const String ts = '2024-01-01T10:00:00.000Z';
        recentExceptionsReader = ({int limit = 20}) => [
              {
                'type': 'StateError',
                'message': 'exact time error',
                'stackHead': 'at exact()',
                'library': 'test',
                'fatal': false,
                'time': ts,
              },
            ];

        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{'since': ts},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        // Strictly after means same-timestamp is excluded.
        expect(decoded['count'], equals(0));
        expect((decoded['exceptions'] as List).isEmpty, isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (l) Unparseable since is treated as no filter (graceful fallback).
    // -------------------------------------------------------------------------

    test(
      '(l) unparseable since: treated as no filter, returns full list',
      () async {
        recentExceptionsReader = ({int limit = 20}) => [
              {
                'type': 'StateError',
                'message': 'any error',
                'stackHead': 'at any()',
                'library': 'test',
                'fatal': false,
                'time': '2024-01-01T10:00:00.000Z',
              },
            ];

        final response = await aiTestExceptionsHandler(
          'ext.dusk.exceptions',
          <String, String>{'since': 'not-a-date'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        // Graceful fallback: no filter applied, 1 entry returned.
        expect(decoded['count'], equals(1));
      },
    );
  });
}
