import 'dart:developer' as developer;

import 'package:fluttersdk_artisan/artisan.dart';

import '../dusk_error_capture.dart';
import '../utils/dusk_response.dart';
import '../utils/error_envelope.dart';

// ---------------------------------------------------------------------------
// MCP descriptor constants -- consumed by DuskArtisanProvider.mcpTools()
// ---------------------------------------------------------------------------

/// MCP tool name for the exception reader.
const String kDuskExceptionsMcpName = 'dusk_exceptions';

/// VM Service extension method name for the exception reader.
const String kDuskExceptionsMcpExtension = 'ext.dusk.exceptions';

// ---------------------------------------------------------------------------
// Function-pointer indirection -- mirrors pendingHttpCountReader + recentLogsReader
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
/// Merges entries from two sources, newest-first, deduped by
/// `(type, message, stackHead)`, then clips to `limit`:
///
/// 1. [recentCapturedExceptions]: in-package ring buffer of non-fatal
///    [FlutterError]s (incl. overflow). Present without telescope.
/// 2. [recentExceptionsReader]: function-pointer indirection wired by
///    `MagicTelescopeIntegration`. Defaults to an empty list when telescope
///    is absent (graceful no-op).
///
/// Params (all string-valued):
/// - `limit` (optional, default 20): maximum entries in the merged response.
/// - `since` (optional): ISO8601 timestamp string. When present, only
///   exceptions whose `time` is strictly after `since` are returned. When
///   absent or unparseable, the full cumulative list is returned unchanged
///   (backward compatible).
///
/// Response JSON:
/// ```json
/// {
///   "exceptions": [
///     {"type": "overflow", "message": "...", "stackHead": "...",
///      "library": "rendering library", "fatal": false, "time": "..."}
///   ],
///   "count": 1
/// }
/// ```
Future<developer.ServiceExtensionResponse> aiTestExceptionsHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Parse params -- limit is optional; fall back to 20 when absent.
    //    since is optional; null means no time filter (full cumulative list).
    final int limit = _parseInt(params['limit']) ?? 20;
    final DateTime? since = _parseIso8601(params['since']);

    // 2. Collect from both sources: in-package buffer (non-fatal FlutterErrors)
    //    and the telescope reader (when wired). Use a generous fetch so the
    //    merge has enough candidates before the final limit clip.
    final List<Map<String, dynamic>> buffered = recentCapturedExceptions(
      limit: limit,
    );
    final List<Map<String, dynamic>> telescope = recentExceptionsReader(
      limit: limit,
    );

    // 3. Merge, dedup by (type, message, stackHead), keep newest-first, then
    //    clip to limit. The in-package buffer is already newest-first; telescope
    //    entries follow it so buffered entries win on dedup conflicts.
    final Set<String> seen = <String>{};
    final List<Map<String, dynamic>> merged = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> entry in [...buffered, ...telescope]) {
      final String key =
          '${entry['type']} ${entry['message']} ${entry['stackHead']}';
      if (seen.add(key)) {
        merged.add(entry);
      }
    }

    // 4. Apply the optional since filter -- keep only entries whose time is
    //    strictly after the since threshold. Entries with an unparseable or
    //    missing time field pass through unchanged so malformed entries are
    //    visible rather than silently dropped.
    final List<Map<String, dynamic>> filtered = since == null
        ? merged
        : merged.where((Map<String, dynamic> entry) {
            final String? rawTime = entry['time'] as String?;
            if (rawTime == null) return true;
            final DateTime? entryTime = _parseIso8601(rawTime);
            if (entryTime == null) return true;
            return entryTime.isAfter(since);
          }).toList();

    final List<Map<String, dynamic>> exceptions =
        filtered.length > limit ? filtered.sublist(0, limit) : filtered;

    // 5. Return the structured envelope.
    return duskResult(<String, dynamic>{
      'exceptions': exceptions,
      'count': exceptions.length,
    });
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.exceptions: unexpected error: $e\n$st',
      name: 'fluttersdk_dusk',
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

/// Parses [raw] as an ISO8601 [DateTime]. Returns null when [raw] is null,
/// empty, or not a valid ISO8601 string. Used for the `since` param guard:
/// an unparseable value is treated as absent (no filter), never as an error.
DateTime? _parseIso8601(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw);
  } catch (_) {
    return null;
  }
}
