import 'dart:convert';
import 'dart:developer' as developer;

import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/error_envelope.dart';

// ---------------------------------------------------------------------------
// MCP descriptor constants — consumed by DuskArtisanProvider.mcpTools()
// ---------------------------------------------------------------------------

/// MCP tool name for the console log reader.
const String kDuskConsoleMcpName = 'dusk_console';

/// VM Service extension method name for the console log reader.
const String kDuskConsoleMcpExtension = 'ext.dusk.console';

// ---------------------------------------------------------------------------
// Function-pointer indirection — same pattern as pendingHttpCountReader
// ---------------------------------------------------------------------------

/// Reader for recent log entries from TelescopeStore.
///
/// Defaults to a function that returns an empty list so dusk compiles and
/// runs without telescope present (missing-telescope graceful path).
///
/// Hosts that ship `fluttersdk_telescope` wire the real source by assigning:
///
/// ```dart
/// recentLogsReader = ({int limit = 50, String? minLevel}) =>
///     TelescopeStore.recentLogs(limit: limit, minLevel: minLevel);
/// ```
///
/// The indirection keeps dusk's pubspec free of a telescope dependency while
/// letting the console handler still read real logs when telescope is wired.
///
/// **Contract**: set-once-per-isolate from `MagicTelescopeIntegration.install()`.
/// Reset to the empty-list default by `MagicTelescopeIntegration.resetForTesting()`
/// so downstream tests asserting the missing-telescope default do not see leaked
/// bindings.
List<Map<String, dynamic>> Function({int limit, String? minLevel})
    recentLogsReader = ({int limit = 50, String? minLevel}) => const [];

// ---------------------------------------------------------------------------
// Aggregator
// ---------------------------------------------------------------------------

/// Registers the `ext.dusk.console` VM Service extension.
///
/// Idempotent via [registerExtensionIdempotent]. Call from
/// [registerAllDuskExtensions] once during [DuskPlugin.install].
void registerConsoleExtensions() {
  registerExtensionIdempotent(kDuskConsoleMcpExtension, aiTestConsoleHandler);
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/// Handler for the `ext.dusk.console` VM Service extension.
///
/// Reads recent log entries from the telescope store via the
/// [recentLogsReader] function-pointer indirection. When telescope is not
/// installed the default reader returns an empty list (graceful no-op).
///
/// Params (all string-valued):
/// - `limit` (optional, default 50): maximum number of log entries to return.
/// - `minLevel` (optional): minimum severity level to include (e.g. `'WARNING'`,
///   `'ERROR'`). Passed verbatim to the reader; filtering semantics are owned
///   by the telescope store.
///
/// Response JSON:
/// ```json
/// { "logs": [{"level": "INFO", "message": "...", "time": "...", "logger": "..."}], "count": 2 }
/// ```
Future<developer.ServiceExtensionResponse> aiTestConsoleHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Parse params — both are optional; fall back to defaults when absent.
    final int limit = _parseInt(params['limit']) ?? 50;
    final String? minLevel =
        params['minLevel']?.isNotEmpty == true ? params['minLevel'] : null;

    // 2. Read logs through the function-pointer so the telescope package is
    //    never a hard dependency of dusk (pre-existing xml/image conflict
    //    blocks adding telescope as a path-dep; indirection is the only safe
    //    cross-package wiring approach).
    final List<Map<String, dynamic>> logs = recentLogsReader(
      limit: limit,
      minLevel: minLevel,
    );

    // 3. Return the structured envelope — count lets callers skip iterating the
    //    list when only the total matters.
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'logs': logs,
        'count': logs.length,
      }),
    );
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.console: unexpected error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.console: $e',
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
