import 'dart:convert';
import 'dart:developer' as developer;

import 'package:fluttersdk_artisan/artisan.dart';

import '../dusk_log_capture.dart';
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
/// Merges entries from two sources, newest-first, deduped by
/// `(level, message, logger)`, then clips to `limit`:
///
/// 1. [recentCapturedLogs] — in-package ring buffer fed by the [debugPrint]
///    override installed by [installLogCapture]. Present without telescope.
///    Captures every call that routes through the [debugPrint] global callback
///    (`debugPrint(...)`, `print(...)`, any Flutter framework path). Does NOT
///    capture direct `dart:developer` `log()` calls that bypass [debugPrint].
/// 2. [recentLogsReader] — function-pointer indirection wired by
///    `MagicTelescopeIntegration.install()`. Defaults to an empty list when
///    telescope is absent (graceful no-op). When telescope is wired it returns
///    all log sources including `Logger.root.onRecord` from `package:logging`
///    (which covers direct `developer.log()` calls when the app configures
///    hierarchical logging).
///
/// Params (all string-valued):
/// - `limit` (optional, default 50): maximum number of log entries to return.
/// - `minLevel` (optional): minimum severity level to include (e.g. `'WARNING'`,
///   `'SEVERE'`). Applied to both sources; the in-package buffer uses the same
///   level names as `dart:logging` (INFO, WARNING, SEVERE, SHOUT, ...).
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

    // 2. Collect from both sources: in-package buffer (debugPrint capture) and
    //    the telescope reader (when wired). Use a generous fetch so the merge
    //    has enough candidates before the final limit clip.
    final List<Map<String, dynamic>> buffered = recentCapturedLogs(
      limit: limit,
      minLevel: minLevel,
    );
    final List<Map<String, dynamic>> telescope = recentLogsReader(
      limit: limit,
      minLevel: minLevel,
    );

    // 3. Merge, dedup by (level, message, logger), keep newest-first (in-package
    //    buffer already newest-first; telescope entries follow so buffered entries
    //    win on dedup conflicts), then clip to limit.
    final Set<String> seen = <String>{};
    final List<Map<String, dynamic>> merged = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> entry in <Map<String, dynamic>>[
      ...buffered,
      ...telescope,
    ]) {
      final String key =
          '${entry['level']} ${entry['message']} ${entry['logger']}';
      if (seen.add(key)) {
        merged.add(entry);
      }
    }

    final List<Map<String, dynamic>> logs =
        merged.length > limit ? merged.sublist(0, limit) : merged;

    // 4. Return the structured envelope — count lets callers skip iterating the
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
