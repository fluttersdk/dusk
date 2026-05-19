import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/error_envelope.dart';

/// Signature for the injectable evaluate function.
///
/// Accepts a Dart [expression] string and returns its string representation.
/// Implementations perform the actual VM Service `evaluate` RPC call; the
/// default production implementation is wired by the CLI-side artisan consumer
/// (TinkerCommand / MCP `flutter_evaluate` tool) directly against the VM
/// Service. The host-side extension is a slim dispatch shim that validates the
/// param and formats the response envelope.
typedef DuskEvaluator = Future<String> Function(String expression);

/// `ext.dusk.evaluate` handler.
///
/// Dispatches [expression] through [evaluator] and wraps the result in the
/// standard V3 response envelope:
///
/// ```json
/// { "expression": "<expr>", "result": "<@Instance JSON or toString>" }
/// ```
///
/// When [evaluator] is `null`, the handler falls back to a no-op sentinel
/// that returns the expression echoed back. In production the artisan CLI
/// or MCP layer injects the real VM Service evaluate RPC. For host-side
/// extension registration, the sentinel signals to the CLI that
/// `ext.dusk.evaluate` is available so the consumer can detect and call the
/// VM evaluate RPC from the CLI side without a second round-trip.
///
/// Params:
/// - `expression` (required): the Dart expression to evaluate inside the
///   running isolate.
///
/// Error responses:
/// - Missing `expression`: [developer.ServiceExtensionResponse.extensionError]
///   with `{"error": "expression param is required"}`.
/// - Evaluator throws: [developer.ServiceExtensionResponse.extensionError]
///   with `{"error": "<message>", "stackTrace": "<trace>"}`.
Future<developer.ServiceExtensionResponse> extDuskEvaluateHandler(
  String method,
  Map<String, String> params, {
  @visibleForTesting DuskEvaluator? evaluator,
}) async {
  final String? expression = params['expression'];

  if (expression == null || expression.isEmpty) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'expression param is required',
        DuskErrorEnvelope.missingParam('expression'),
      ),
    );
  }

  // 1. Resolve the evaluator: injected stub in tests, sentinel no-op otherwise.
  final DuskEvaluator resolve = evaluator ?? _sentinelEvaluator;

  try {
    // 2. Delegate evaluation.
    final String result = await resolve(expression);

    // 3. Return the standard V3 envelope.
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'expression': expression,
        'result': result,
      }),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.evaluate error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Sentinel evaluator used when no real VM Service evaluator is injected.
///
/// The host-side `ext.dusk.evaluate` extension is a discovery signal for the
/// CLI layer (mirrors the `ext.tinker.evaluate` sentinel in magic_tinker).
/// Actual Dart expression evaluation is performed CLI-side via the VM Service
/// `evaluate` RPC, which has access to the isolate's lexical scope. Returning
/// a sentinel string ensures the CLI can detect the extension is wired without
/// requiring a real isolate evaluate call at registration time.
Future<String> _sentinelEvaluator(String expression) async {
  return '<eval-via-vm-service: $expression>';
}

/// Registers the `ext.dusk.evaluate` VM Service extension.
///
/// Guards behind [kDebugMode] so release builds tree-shake this branch on
/// every platform (dart2js for web, dart2native for AOT). Call this from the
/// `registerAllDuskExtensions` aggregator once Step 13 consolidates the
/// wire-up.
///
/// Idempotent: [registerExtensionIdempotent] swallows the [ArgumentError]
/// thrown by [developer.registerExtension] on hot-restart duplicate
/// registration.
void registerEvaluateExtension() {
  if (!kDebugMode) return;
  registerExtensionIdempotent(
    'ext.dusk.evaluate',
    (String method, Map<String, String> params) =>
        extDuskEvaluateHandler(method, params),
  );
}
