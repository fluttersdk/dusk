import 'dart:convert';
import 'dart:developer' as developer;

import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/error_envelope.dart';

// ---------------------------------------------------------------------------
// MCP descriptor constants — consumed by DuskArtisanProvider.mcpTools()
// ---------------------------------------------------------------------------

/// MCP tool name for the exception reader.
const String kDuskExceptionsMcpName = 'dusk_exceptions';

/// VM Service extension method name for the exception reader.
const String kDuskExceptionsMcpExtension = 'ext.dusk.exceptions';

// ---------------------------------------------------------------------------
// Function-pointer indirection — mirrors pendingHttpCountReader + recentLogsReader
// ---------------------------------------------------------------------------

/// Reader for recent exception entries from TelescopeStore.
///
/// Defaults to a function that returns an empty list so dusk compiles and
/// runs without telescope present (missing-telescope graceful path).
///
/// Hosts that ship `fluttersdk_telescope` wire the real source by assigning:
///
/// ```dart
/// recentExceptionsReader = ({int limit = 20}) =>
///     TelescopeStore.recentExceptions(limit: limit);
/// ```
///
/// The indirection keeps dusk's pubspec free of a telescope dependency.
///
/// **Contract**: set-once-per-isolate from `MagicTelescopeIntegration.install()`.
/// Reset to the empty-list default by `MagicTelescopeIntegration.resetForTesting()`
/// so downstream tests asserting the missing-telescope default do not see leaked
/// bindings.
List<Map<String, dynamic>> Function({int limit}) recentExceptionsReader =
    ({int limit = 20}) => const [];

// ---------------------------------------------------------------------------
// Aggregator
// ---------------------------------------------------------------------------

/// Registers the `ext.dusk.exceptions` VM Service extension.
///
/// Idempotent via [registerExtensionIdempotent]. Call from
/// [registerAllDuskExtensions] once during [DuskPlugin.install].
void registerExceptionsExtensions() {
  registerExtensionIdempotent(
    kDuskExceptionsMcpExtension,
    aiTestExceptionsHandler,
  );
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/// Handler for the `ext.dusk.exceptions` VM Service extension.
///
/// Reads recent exception entries from the telescope store via the
/// [recentExceptionsReader] function-pointer indirection. When telescope is
/// not installed the default reader returns an empty list (graceful no-op).
///
/// Params (all string-valued):
/// - `limit` (optional, default 20): maximum number of exception entries to
///   return.
///
/// Response JSON:
/// ```json
/// {
///   "exceptions": [
///     {"type": "ArgumentError", "message": "...", "stackHead": "...", "time": "..."}
///   ],
///   "count": 1
/// }
/// ```
///
/// `stackHead` contains the first 3 lines of the stack trace when the
/// reader supplies it; the handler passes through whatever the reader
/// returns without further truncation (truncation lives in the telescope
/// store or the host wiring).
Future<developer.ServiceExtensionResponse> aiTestExceptionsHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Parse params — limit is optional; fall back to 20 when absent.
    final int limit = _parseInt(params['limit']) ?? 20;

    // 2. Read exceptions through the function-pointer indirection.
    final List<Map<String, dynamic>> exceptions = recentExceptionsReader(
      limit: limit,
    );

    // 3. Return the structured envelope.
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'exceptions': exceptions,
        'count': exceptions.length,
      }),
    );
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.exceptions: unexpected error: $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.exceptions: $e',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Parses [raw] as a positive integer. Returns null when null, empty, or
/// not a valid integer.
int? _parseInt(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
}
