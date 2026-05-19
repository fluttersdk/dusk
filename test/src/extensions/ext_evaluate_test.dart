import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_evaluate.dart';
import 'package:fluttersdk_dusk/src/utils/error_envelope.dart';

void main() {
  group('ext.dusk.evaluate', () {
    // -------------------------------------------------------------------------
    // (a) Missing expression parameter returns extensionError
    // -------------------------------------------------------------------------

    test('(a) missing expression param returns extensionError', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskEvaluateHandler(
        'ext.dusk.evaluate',
        const <String, String>{},
        evaluator: null,
      );

      expect(
        response.errorCode,
        equals(developer.ServiceExtensionResponse.extensionError),
      );

      // Step 3.3: error responses now carry the structured envelope wrapper.
      // The original free-form message is recoverable via parseMessage; the
      // envelope's type field is the new typed-failure surface.
      expect(
        parseMessageFromErrorDetail(response.errorDetail!),
        contains('expression'),
      );
      final Map<String, dynamic>? envelope =
          parseEnvelopeFromErrorDetail(response.errorDetail!);
      expect(envelope, isNotNull);
      expect(envelope!['type'], equals('missing_param'));
    });

    // -------------------------------------------------------------------------
    // (b) Simple expression returns envelope with expression + result keys
    // -------------------------------------------------------------------------

    test('(b) simple expression returns correct envelope shape', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskEvaluateHandler(
        'ext.dusk.evaluate',
        const <String, String>{'expression': '1 + 1'},
        evaluator: (String expr) async => '2',
      );

      expect(response.errorCode, isNull);

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['expression'], equals('1 + 1'));
      expect(body['result'], equals('2'));
    });

    // -------------------------------------------------------------------------
    // (c) Magic facade call passes expression to evaluator and returns result
    // -------------------------------------------------------------------------

    test(
      '(c) magic facade call expression passes through evaluator unchanged',
      () async {
        const String expr =
            "Magic.find<MonitorController>().rxState.value.toString()";

        String? capturedExpr;
        final developer.ServiceExtensionResponse response =
            await extDuskEvaluateHandler(
          'ext.dusk.evaluate',
          const <String, String>{
            'expression':
                "Magic.find<MonitorController>().rxState.value.toString()",
          },
          evaluator: (String e) async {
            capturedExpr = e;
            return 'MonitorState{status: loaded}';
          },
        );

        expect(capturedExpr, equals(expr));
        expect(response.errorCode, isNull);

        final Map<String, dynamic> body =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(body['expression'], equals(expr));
        expect(body['result'], equals('MonitorState{status: loaded}'));
      },
    );

    // -------------------------------------------------------------------------
    // (d) Evaluator throwing returns extensionError with error detail
    // -------------------------------------------------------------------------

    test(
      '(d) evaluator error (compile error) returns extensionError',
      () async {
        final developer.ServiceExtensionResponse response =
            await extDuskEvaluateHandler(
          'ext.dusk.evaluate',
          const <String, String>{'expression': 'invalid dart !!syntax!!'},
          evaluator: (_) async =>
              throw Exception('CompilationError: unexpected token'),
        );

        expect(
          response.errorCode,
          equals(developer.ServiceExtensionResponse.extensionError),
        );

        // Step 3.3: error responses now carry the structured envelope.
        expect(
          parseMessageFromErrorDetail(response.errorDetail!),
          contains('CompilationError'),
        );
        final Map<String, dynamic>? envelope =
            parseEnvelopeFromErrorDetail(response.errorDetail!);
        expect(envelope, isNotNull);
        expect(envelope!['type'], equals('unexpected'));
      },
    );

    // -------------------------------------------------------------------------
    // (e) registerEvaluateExtension is defined (compile-time check)
    // -------------------------------------------------------------------------

    test('(e) registerEvaluateExtension is callable without error', () {
      // registerEvaluateExtension guards behind kDebugMode so it no-ops in
      // test mode. Calling it should not throw.
      expect(() => registerEvaluateExtension(), returnsNormally);
    });

    test(
      '(f) handler with no injected evaluator falls back to sentinel',
      () async {
        final developer.ServiceExtensionResponse response =
            await extDuskEvaluateHandler(
          'ext.dusk.evaluate',
          const <String, String>{'expression': 'someExpr()'},
          // evaluator omitted → _sentinelEvaluator fires.
        );

        expect(response.errorCode, isNull);
        final Map<String, dynamic> body =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(body['expression'], equals('someExpr()'));
        expect(
          body['result'] as String,
          contains('<eval-via-vm-service:'),
        );
      },
    );
  });
}
