import 'package:flutter/foundation.dart';

/// Maximum number of log entries retained in the in-package ring buffer.
///
/// Matches the cap used by [dusk_error_capture] for consistency across
/// dusk's own in-package capture facilities.
const int _kCaptureCap = 50;

/// Process-global guard for the [installLogCapture] / [uninstallLogCapture]
/// pair. Deliberately independent of `DuskPlugin._installCount` so the capture
/// is install/uninstall-able on its own from a test via `addTearDown`.
bool _installed = false;

/// The debugPrint callback that was active before [installLogCapture] ran.
/// Re-captured on every install so the chained `_prior(...)` always
/// points at the handler that was live at install time.
///
/// Initialized to [debugPrintThrottled] (Flutter's default) rather than null
/// so the field is non-nullable and the restore in [uninstallLogCapture] can
/// assign directly to [debugPrint] without a null check.
DebugPrintCallback _prior = debugPrintThrottled;

/// Newest-first ring buffer of captured log entries, capped at [_kCaptureCap].
///
/// Each entry is `{level, levelValue, message, logger, time}` to mirror the
/// shape expected by `ext.dusk.console` (and the shape telescope's
/// `TelescopeStore.recentLogs` returns when wired).
final List<Map<String, dynamic>> _buffer = <Map<String, dynamic>>[];

// ---------------------------------------------------------------------------
// Numeric level values (mirrors dart:logging Level constants, no import needed)
// ---------------------------------------------------------------------------

/// Maps a level name (case-insensitive) to its numeric value.
///
/// Mirrors `dart:logging`'s `Level` constants so level comparisons work
/// consistently whether the app uses `package:logging` or not.
const Map<String, int> _levelValues = <String, int>{
  'all': 0,
  'finest': 300,
  'finer': 400,
  'fine': 500,
  'config': 700,
  'info': 800,
  'warning': 900,
  'severe': 1000,
  'shout': 1200,
  'off': 2000,
};

/// Returns the numeric value for [levelName], case-insensitive. Unknown names
/// return 800 (INFO) as a safe default.
int _levelValueFor(String levelName) =>
    _levelValues[levelName.toLowerCase()] ?? 800;

/// Returns true when [entryLevel] meets or exceeds [minLevel].
bool _meetsLevel(String entryLevel, String minLevel) =>
    _levelValueFor(entryLevel) >= _levelValueFor(minLevel);

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Installs the in-package [debugPrint] log capture.
///
/// Saves the current [debugPrint] callback, then replaces it with an
/// interceptor that records the message into a bounded ring buffer AND calls
/// the prior callback so the original console/DevTools presentation is
/// preserved (chain-preserve pattern). Idempotent: a second install while
/// already installed is a no-op.
///
/// **Capture scope (without telescope)**
/// - Captures every call that routes through the [debugPrint] global callback:
///   `debugPrint(...)`, `print(...)` (via Flutter's default callback), and
///   any framework path that calls [debugPrint] directly.
/// - Does NOT capture `dart:developer` `log()` calls that bypass [debugPrint]
///   entirely. Those are captured only when `fluttersdk_telescope` is installed
///   and its `LogWatcher` is wired (it subscribes to `Logger.root.onRecord`
///   from `package:logging`, which the Dart VM routes `developer.log()` through
///   when the app configures hierarchical logging). Without telescope, direct
///   `developer.log(message, name: 'my.logger')` calls are not surfaced by
///   `ext.dusk.console`.
///
/// Wired into `DuskPlugin.install()` so the capture is active for every debug
/// session. Also callable directly from tests with a matching
/// [uninstallLogCapture] in `addTearDown`.
void installLogCapture() {
  if (_installed) {
    return;
  }

  _prior = debugPrint; // non-nullable: debugPrint is always set
  debugPrint = _captureThenChain;
  _installed = true;
}

/// Restores the callback that was active before [installLogCapture].
///
/// No-op when capture is not currently installed. Never sets [debugPrint] to
/// null beyond restoring whatever the prior callback was.
void uninstallLogCapture() {
  if (!_installed) {
    return;
  }

  debugPrint = _prior;
  _prior = debugPrintThrottled; // reset to default so prior is never stale
  _installed = false;
}

/// Returns the most recently captured log entries, newest-first, up to
/// [limit] entries. When [minLevel] is provided (e.g. `'WARNING'`), only
/// entries at or above that level are included.
///
/// Used by `ext.dusk.console` to surface in-package log entries even when
/// `fluttersdk_telescope` is absent. Returns defensive copies so callers
/// cannot mutate the buffer.
List<Map<String, dynamic>> recentCapturedLogs({
  int limit = 20,
  String? minLevel,
}) {
  final Iterable<Map<String, dynamic>> candidates = minLevel != null
      ? _buffer.where(
          (Map<String, dynamic> e) =>
              _meetsLevel(e['level'] as String, minLevel),
        )
      : _buffer;

  final List<Map<String, dynamic>> list = candidates.toList();
  final int count = limit < list.length ? limit : list.length;
  return List<Map<String, dynamic>>.generate(
    count < 0 ? 0 : count,
    (int index) => Map<String, dynamic>.of(list[index]),
  );
}

/// Clears the buffer and uninstalls the capture. Test-only.
@visibleForTesting
void resetCapturedLogsForTesting() {
  uninstallLogCapture();
  _buffer.clear();
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Records [message] then chains the prior debugPrint callback.
void _captureThenChain(String? message, {int? wrapWidth}) {
  // 1. Record into the bounded buffer first so a throwing prior handler cannot
  //    starve the capture.
  _record(message ?? '');

  // 2. Preserve the original presentation (console dump / DevTools / test
  //    binding output). Never swallow.
  _prior(message, wrapWidth: wrapWidth);
}

/// Appends a log entry for [message], newest-first, capped at [_kCaptureCap].
///
/// Every debugPrint message is stored as level `INFO` (value 800), matching
/// Dart's `Level.INFO` numeric value and the expected shape of
/// `ext.dusk.console` log entries.
void _record(String message) {
  // 1. Build the entry in the same shape as telescope's LogRecordEntry.toJson
  //    so the merge+dedup in ext_console.dart can key by (level, message, logger).
  final Map<String, dynamic> entry = <String, dynamic>{
    'level': 'INFO',
    'levelValue': 800,
    'message': message,
    'logger': 'debugPrint',
    'time': DateTime.now().toUtc().toIso8601String(),
  };

  // 2. Insert newest-first and enforce the cap, evicting the oldest tail entry
  //    when full. No dedup index needed for logs: repeated identical messages
  //    are intentional (unlike RenderFlex overflows which fire once per layout).
  _buffer.insert(0, entry);

  if (_buffer.length > _kCaptureCap) {
    _buffer.removeLast();
  }
}
