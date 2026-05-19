import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:meta/meta.dart';

/// Signature for the test-injectable `Process.run` hook.
///
/// Mirrors [Process.run] just enough for the POSIX `pgrep` / `ps` probes the
/// reaper relies on. Production code keeps the default ([Process.run]); tests
/// install a stub that returns scripted [ProcessResult] objects per
/// (executable, arguments) tuple. Dart cannot mock top-level functions, so
/// this typedef is the seam.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// Signature for the test-injectable [Process.killPid] hook used by both
/// [killChromeAndProfile] and [reapOrphans].
typedef KillFunction = bool Function(int pid, ProcessSignal signal);

/// Signature for the test-injectable liveness probe used inside
/// [killChromeAndProfile] to decide whether to escalate to SIGKILL after the
/// SIGTERM grace window.
typedef LivenessProbe = bool Function(int pid);

/// Hook for tests to inject a custom subprocess runner without touching the
/// real `pgrep` / `ps` binaries on the host. Defaults to [Process.run].
@visibleForTesting
ProcessRunner chromeReaperRunner = Process.run;

/// Hook for tests to inject a custom kill implementation. Defaults to
/// [Process.killPid]. The reaper uses it twice per Chrome PID: once as a
/// liveness probe with [ProcessSignal.sigterm] / [ProcessSignal.sigkill] and
/// once for the actual signal delivery.
@visibleForTesting
KillFunction chromeReaperKiller = Process.killPid;

/// Hook for tests to inject a custom liveness probe. Defaults to a
/// `ps -p <pid>` subprocess check (exit code 0 means alive). The reaper uses
/// it once after the SIGTERM grace window to decide whether the Chrome
/// process needs SIGKILL escalation. Tests stub this directly to control the
/// cascade without spawning real processes.
@visibleForTesting
LivenessProbe chromeReaperIsAlive = _defaultIsAlive;

bool _defaultIsAlive(int pid) {
  try {
    final ProcessResult result = Process.runSync('ps', <String>['-p', '$pid']);
    return result.exitCode == 0;
  } catch (_) {
    // ps unavailable (rare on POSIX): assume gone so the cascade does not
    // loop SIGKILL on an already-dead process.
    return false;
  }
}

/// Hook for tests to override the host OS check. Defaults to
/// [Platform.isWindows]. Dart's [Platform.isWindows] is a host-runner
/// constant; the only way to exercise the Windows-fallback branch from a
/// macOS / Linux test runner is to flip this flag.
@visibleForTesting
bool chromeReaperIsWindows = Platform.isWindows;

/// Grace period between SIGTERM and the SIGKILL escalation inside
/// [killChromeAndProfile]. Defaults to two seconds; tests override to
/// [Duration.zero] to keep the suite snappy.
@visibleForTesting
Duration chromeReaperGrace = const Duration(seconds: 2);

/// Hook for tests to capture the single Windows-fallback warning emitted per
/// session. Defaults to null, in which case the warning routes through
/// [developer.log] under the `fluttersdk_dusk.chrome_reaper` logger name.
@visibleForTesting
void Function(String message)? chromeReaperLogger;

/// Marker that disambiguates Flutter's Chrome from any other browser process
/// in the user's session. Filters both the reaper's `pgrep -fl` output and
/// the capture step's `ps -o command=` output.
const String _chromeProfileMarker = 'flutter_tools_chrome_device';

/// Pattern matching `--user-data-dir=<path>` inside a Chrome command line.
/// The path stops at the next whitespace; Chrome never wraps the value in
/// quotes when launched by `flutter run -d chrome`.
final RegExp _userDataDirPattern = RegExp(r'--user-data-dir=(\S+)');

/// Session-scoped flag for the once-per-session Windows warning.
bool _windowsWarningEmitted = false;

/// Resets the once-per-session Windows warning flag. Tests call this from
/// `setUp` / `tearDown` so per-test log assertions never inherit state from
/// the previous case.
@visibleForTesting
void chromeReaperResetWindowsWarningForTesting() {
  _windowsWarningEmitted = false;
}

/// Emits the Windows POSIX-only warning at most once per session and returns
/// `true` to signal "skip the rest of the body". Routes through
/// [chromeReaperLogger] when present (tests) or [developer.log] otherwise
/// (production).
bool _windowsSkip() {
  if (!chromeReaperIsWindows) return false;
  if (!_windowsWarningEmitted) {
    _windowsWarningEmitted = true;
    const String message =
        'fluttersdk_dusk.chrome_reaper: POSIX-only utility; Windows skipped. '
        'Clean orphan Chrome instances manually with '
        '`taskkill /T /F /IM chrome.exe` after a failed session.';
    final void Function(String message)? logger = chromeReaperLogger;
    if (logger != null) {
      logger(message);
    } else {
      developer.log(message, name: 'fluttersdk_dusk.chrome_reaper');
    }
  }
  return true;
}

/// Captures the Chrome top-level PID spawned by a `flutter run -d chrome`
/// process whose PID is [parentPid].
///
/// Implementation:
///
///   1. `pgrep -P <parentPid>` enumerates Flutter's direct children.
///   2. For each child, `ps -p <child> -o command=` reads the full command
///      line. The first child whose command contains
///      [`flutter_tools_chrome_device`] is the Chrome top-level process; its
///      PID is returned.
///
/// Returns `null` when:
///
/// - [Platform.isWindows] is true (no `pgrep` on Windows; the function logs
///   a one-shot warning per session and returns null).
/// - `pgrep -P` exits non-zero (no children, or `pgrep` is missing).
/// - No child command line carries the chrome profile marker.
/// - Any spawn throws — the error is swallowed and `null` returned so the
///   caller can degrade gracefully.
Future<int?> captureChromePid({required int parentPid}) async {
  if (_windowsSkip()) return null;

  try {
    final ProcessResult result = await chromeReaperRunner(
      'pgrep',
      <String>['-P', '$parentPid'],
    );
    if (result.exitCode != 0) return null;

    final List<int> children = const LineSplitter()
        .convert(result.stdout as String)
        .map((String s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();

    for (final int child in children) {
      try {
        final ProcessResult ps = await chromeReaperRunner(
          'ps',
          <String>['-p', '$child', '-o', 'command='],
        );
        if (ps.exitCode != 0) continue;
        final String command = (ps.stdout as String).trim();
        if (command.contains(_chromeProfileMarker)) return child;
      } catch (_) {
        // Per-child ps failure is non-fatal; keep scanning siblings.
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Reads the Chrome process [chromePid]'s `--user-data-dir=<path>` argument
/// via `ps -p <pid> -o command=` and returns the matched path. Returns null
/// when:
///
/// - [Platform.isWindows] is true (the function logs a one-shot warning per
///   session and returns null).
/// - `ps` exits non-zero (no such process, or `ps` is missing).
/// - The command line lacks `--user-data-dir`.
/// - The spawn throws.
Future<String?> captureChromeProfileDir({required int chromePid}) async {
  if (_windowsSkip()) return null;

  try {
    final ProcessResult ps = await chromeReaperRunner(
      'ps',
      <String>['-p', '$chromePid', '-o', 'command='],
    );
    if (ps.exitCode != 0) return null;
    final String command = (ps.stdout as String).trim();
    final Match? match = _userDataDirPattern.firstMatch(command);
    return match?.group(1);
  } catch (_) {
    return null;
  }
}

/// Sends SIGTERM to [chromePid], waits [chromeReaperGrace] for a graceful
/// shutdown, then escalates to SIGKILL when [chromeReaperIsAlive] still
/// reports the process alive. Finally, when [tmpProfileDir] is non-null,
/// deletes that directory recursively (best-effort; missing directories and
/// permission errors are swallowed).
///
/// On Windows the function is a no-op and logs a one-shot warning per
/// session.
///
/// Errors thrown by [chromeReaperKiller] are swallowed; the reaper must never
/// surface a kill failure to the caller (worst case: the operator cleans up
/// manually). The directory delete is wrapped in its own try/catch for the
/// same reason.
Future<void> killChromeAndProfile({
  required int chromePid,
  required String? tmpProfileDir,
}) async {
  if (_windowsSkip()) return;

  // 1. Deliver SIGTERM. Failures are non-fatal; the liveness probe below
  //    decides whether to escalate.
  try {
    chromeReaperKiller(chromePid, ProcessSignal.sigterm);
  } catch (_) {
    // Continue to grace + probe + escalate even when SIGTERM throws — the
    // process may still be running.
  }

  // 2. Wait the grace period.
  await Future<void>.delayed(chromeReaperGrace);

  // 3. Liveness probe (default: `ps -p <pid>` exit-code check). Decoupled
  //    from [chromeReaperKiller] so a sigterm-true / sigkill-false stub
  //    inside tests does not accidentally trigger SIGKILL.
  bool stillAlive;
  try {
    stillAlive = chromeReaperIsAlive(chromePid);
  } catch (_) {
    stillAlive = false;
  }

  // 4. Escalate to SIGKILL only when the probe says the process is still
  //    alive. Failures are swallowed.
  if (stillAlive) {
    try {
      chromeReaperKiller(chromePid, ProcessSignal.sigkill);
    } catch (_) {
      // Nothing actionable; the dual-PID cascade is best-effort.
    }
  }

  // 5. Best-effort delete of the tmp profile dir. Absent directories and
  //    permission errors are non-fatal.
  if (tmpProfileDir != null && tmpProfileDir.isNotEmpty) {
    try {
      final Directory dir = Directory(tmpProfileDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // Swallow: a stale profile directory is not worth crashing for.
    }
  }
}

/// Pre-flight reaper: enumerates every running process whose command line
/// carries the [`flutter_tools_chrome_device`] marker via
/// `pgrep -fl flutter_tools_chrome_device` and SIGKILLs each matched PID.
///
/// All failures are swallowed:
///
/// - `pgrep` missing or exit non-zero → no-op return (no orphans to reap).
/// - Per-PID kill failure → logged path-internally, scan continues with the
///   next PID.
///
/// On Windows the function is a no-op and logs a one-shot warning per
/// session.
Future<void> reapOrphans() async {
  if (_windowsSkip()) return;

  try {
    final ProcessResult result = await chromeReaperRunner(
      'pgrep',
      <String>['-fl', _chromeProfileMarker],
    );
    if (result.exitCode != 0) return;

    final List<int> pids = _parsePgrepFullList(result.stdout as String);
    for (final int pid in pids) {
      try {
        chromeReaperKiller(pid, ProcessSignal.sigkill);
      } catch (_) {
        // Per-PID kill failure must not abort the scan of the remaining
        // orphans — keep iterating.
      }
    }
  } catch (_) {
    // pgrep spawn failure (PATH issue, transient OS error) is non-fatal.
  }
}

/// Parses `pgrep -fl` output into a list of PIDs. Each line is
/// `<pid> <commandline>` (space-separated); we keep only the leading PID.
List<int> _parsePgrepFullList(String stdout) {
  final List<int> out = <int>[];
  for (final String line in const LineSplitter().convert(stdout)) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final int spaceIdx = trimmed.indexOf(' ');
    final String pidStr =
        spaceIdx < 0 ? trimmed : trimmed.substring(0, spaceIdx);
    final int? pid = int.tryParse(pidStr);
    if (pid != null) out.add(pid);
  }
  return out;
}
