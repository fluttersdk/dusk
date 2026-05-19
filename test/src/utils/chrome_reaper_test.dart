import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/chrome_reaper.dart';

/// Records every invocation routed through [chromeReaperRunner] so tests can
/// assert on the (executable, arguments) tuples produced by the reaper.
class _RecordedRun {
  const _RecordedRun(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

/// Records every invocation routed through [chromeReaperKiller] so tests can
/// assert the SIGTERM-then-SIGKILL cascade.
class _RecordedKill {
  const _RecordedKill(this.pid, this.signal);

  final int pid;
  final ProcessSignal signal;
}

/// Builds a [chromeReaperRunner] stub that returns scripted [ProcessResult]
/// values keyed by `(executable, firstArgument)`; unknown lookups return an
/// exit-code-2 result so the production code can hit its no-match path.
ProcessRunner _stubRunner(
  Map<String, ProcessResult> table, {
  List<_RecordedRun>? recorder,
}) {
  return (String executable, List<String> arguments,
      {Map<String, String>? environment}) async {
    recorder?.add(_RecordedRun(executable, List<String>.of(arguments)));
    // 1. Build the lookup key from executable + first-argument flag.
    final String key =
        arguments.isEmpty ? executable : '$executable ${arguments.first}';
    return table[key] ??
        ProcessResult(0, 2, '', 'unmocked: $executable ${arguments.join(' ')}');
  };
}

/// Resets every static-injection seam exposed by `chrome_reaper.dart`. Called
/// from `setUp` / `tearDown` so per-test overrides do not leak.
void _resetReaperHooks() {
  chromeReaperRunner = Process.run;
  chromeReaperKiller = Process.killPid;
  chromeReaperIsAlive = (int pid) => false;
  chromeReaperIsWindows = Platform.isWindows;
  chromeReaperGrace = const Duration(seconds: 2);
  chromeReaperLogger = null;
  chromeReaperResetWindowsWarningForTesting();
}

void main() {
  setUp(_resetReaperHooks);
  tearDown(_resetReaperHooks);

  group('captureChromePid', () {
    test('returns Chrome PID on POSIX when pgrep -P + ps marker match',
        () async {
      chromeReaperIsWindows = false;
      final List<_RecordedRun> calls = <_RecordedRun>[];
      chromeReaperRunner = _stubRunner(
        <String, ProcessResult>{
          'pgrep -P': ProcessResult(0, 0, '12345\n67890\n', ''),
          'ps -p': ProcessResult(
            0,
            0,
            '/Applications/Chromium.app/Contents/MacOS/Chromium '
                '--user-data-dir=/tmp/flutter_tools.AAA/flutter_tools_chrome_device.BBB '
                '--remote-debugging-port=12345',
            '',
          ),
        },
        recorder: calls,
      );

      final int? pid = await captureChromePid(parentPid: 999);

      expect(pid, equals(12345));
      // pgrep call has the parent PID and 'chrome' filter token.
      expect(calls.first.executable, equals('pgrep'));
      expect(calls.first.arguments, contains('-P'));
      expect(calls.first.arguments, contains('999'));
    });

    test('returns null on POSIX when pgrep -P exits non-zero (no children)',
        () async {
      chromeReaperIsWindows = false;
      chromeReaperRunner = _stubRunner(<String, ProcessResult>{
        'pgrep -P': ProcessResult(0, 1, '', ''),
      });

      final int? pid = await captureChromePid(parentPid: 999);

      expect(pid, isNull);
    });

    test('returns null on POSIX when no child command line carries the marker',
        () async {
      chromeReaperIsWindows = false;
      chromeReaperRunner = _stubRunner(<String, ProcessResult>{
        'pgrep -P': ProcessResult(0, 0, '5555\n', ''),
        'ps -p': ProcessResult(0, 0, '/usr/bin/some-other-tool --flag', ''),
      });

      final int? pid = await captureChromePid(parentPid: 999);

      expect(pid, isNull);
    });

    test('returns null on Windows and logs the POSIX-only warning once',
        () async {
      chromeReaperIsWindows = true;
      final List<String> logs = <String>[];
      chromeReaperLogger = logs.add;
      bool runnerCalled = false;
      chromeReaperRunner = (String exe, List<String> args,
          {Map<String, String>? environment}) async {
        runnerCalled = true;
        return ProcessResult(0, 0, '', '');
      };

      final int? first = await captureChromePid(parentPid: 1);
      final int? second = await captureChromePid(parentPid: 2);
      final int? third = await reapOrphans().then((_) => null);

      expect(first, isNull);
      expect(second, isNull);
      expect(third, isNull);
      expect(runnerCalled, isFalse,
          reason: 'no subprocess must spawn on Windows');
      // The session-scoped guard fires exactly once.
      expect(logs.length, equals(1));
      expect(logs.single, contains('POSIX-only'));
    });
  });

  group('captureChromeProfileDir', () {
    test('extracts the --user-data-dir path from ps output on POSIX', () async {
      chromeReaperIsWindows = false;
      chromeReaperRunner = _stubRunner(<String, ProcessResult>{
        'ps -p': ProcessResult(
          0,
          0,
          '/Applications/Chromium.app/Contents/MacOS/Chromium '
              '--user-data-dir=/tmp/flutter_tools.X/flutter_tools_chrome_device.Y '
              '--remote-debugging-port=12345',
          '',
        ),
      });

      final String? dir = await captureChromeProfileDir(chromePid: 12345);

      expect(
        dir,
        equals('/tmp/flutter_tools.X/flutter_tools_chrome_device.Y'),
      );
    });

    test('returns null on POSIX when the command line lacks --user-data-dir',
        () async {
      chromeReaperIsWindows = false;
      chromeReaperRunner = _stubRunner(<String, ProcessResult>{
        'ps -p': ProcessResult(0, 0, '/usr/bin/chrome --headless', ''),
      });

      final String? dir = await captureChromeProfileDir(chromePid: 12345);

      expect(dir, isNull);
    });

    test('returns null on Windows without spawning a subprocess', () async {
      chromeReaperIsWindows = true;
      bool runnerCalled = false;
      chromeReaperRunner = (String exe, List<String> args,
          {Map<String, String>? environment}) async {
        runnerCalled = true;
        return ProcessResult(0, 0, '', '');
      };

      final String? dir = await captureChromeProfileDir(chromePid: 1);

      expect(dir, isNull);
      expect(runnerCalled, isFalse);
    });
  });

  group('killChromeAndProfile', () {
    test(
        'sends SIGTERM, waits grace, sends SIGKILL when still alive, deletes '
        'the profile dir on POSIX', () async {
      chromeReaperIsWindows = false;
      chromeReaperGrace = Duration.zero;

      final List<_RecordedKill> kills = <_RecordedKill>[];
      chromeReaperKiller = (int pid, ProcessSignal signal) {
        kills.add(_RecordedKill(pid, signal));
        return true;
      };
      // The liveness probe reports the process still alive after the grace
      // window so the cascade escalates to SIGKILL.
      chromeReaperIsAlive = (int pid) => true;

      final Directory tmp = await Directory.systemTemp.createTemp(
        'chrome_reaper_test_',
      );
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      });

      await killChromeAndProfile(chromePid: 4242, tmpProfileDir: tmp.path);

      expect(kills.length, greaterThanOrEqualTo(2));
      expect(kills.first.pid, equals(4242));
      expect(kills.first.signal, equals(ProcessSignal.sigterm));
      // The last kill in the cascade is SIGKILL.
      expect(kills.last.signal, equals(ProcessSignal.sigkill));
      expect(tmp.existsSync(), isFalse,
          reason: 'profile dir should be removed best-effort');
    });

    test(
        'stops at SIGTERM when the process is no longer alive during the '
        'liveness probe', () async {
      chromeReaperIsWindows = false;
      chromeReaperGrace = Duration.zero;

      final List<_RecordedKill> kills = <_RecordedKill>[];
      chromeReaperKiller = (int pid, ProcessSignal signal) {
        kills.add(_RecordedKill(pid, signal));
        return true;
      };
      // The liveness probe reports the process is no longer alive after the
      // grace window so the cascade short-circuits before SIGKILL.
      chromeReaperIsAlive = (int pid) => false;

      await killChromeAndProfile(chromePid: 4242, tmpProfileDir: null);

      final bool sawSigkill =
          kills.any((_RecordedKill k) => k.signal == ProcessSignal.sigkill);
      expect(sawSigkill, isFalse);
      expect(kills, hasLength(1));
      expect(kills.first.signal, equals(ProcessSignal.sigterm));
    });

    test('is a no-op on Windows without invoking the killer', () async {
      chromeReaperIsWindows = true;
      bool killerCalled = false;
      chromeReaperKiller = (int pid, ProcessSignal signal) {
        killerCalled = true;
        return true;
      };

      await killChromeAndProfile(chromePid: 1, tmpProfileDir: null);

      expect(killerCalled, isFalse);
    });

    test(
        'tolerates a missing or already-deleted tmpProfileDir without '
        'throwing', () async {
      chromeReaperIsWindows = false;
      chromeReaperGrace = Duration.zero;
      chromeReaperKiller = (int pid, ProcessSignal signal) => false;

      await killChromeAndProfile(
        chromePid: 4242,
        tmpProfileDir:
            '/tmp/this-path-must-not-exist-${DateTime.now().microsecondsSinceEpoch}',
      );
      // Reaching this point without throwing IS the assertion.
    });
  });

  group('reapOrphans', () {
    test(
        'on POSIX runs pgrep -fl with the chrome marker and SIGKILLs every '
        'matched PID', () async {
      chromeReaperIsWindows = false;
      final List<_RecordedRun> calls = <_RecordedRun>[];
      chromeReaperRunner = _stubRunner(
        <String, ProcessResult>{
          'pgrep -fl': ProcessResult(
            0,
            0,
            '111 flutter_tools_chrome_device profile path-A\n'
                '222 flutter_tools_chrome_device profile path-B\n',
            '',
          ),
        },
        recorder: calls,
      );

      final List<_RecordedKill> kills = <_RecordedKill>[];
      chromeReaperKiller = (int pid, ProcessSignal signal) {
        kills.add(_RecordedKill(pid, signal));
        return true;
      };

      await reapOrphans();

      expect(calls.single.executable, equals('pgrep'));
      expect(calls.single.arguments, contains('-fl'));
      expect(
        calls.single.arguments,
        contains('flutter_tools_chrome_device'),
      );
      expect(kills.map((_RecordedKill k) => k.pid).toList(),
          equals(<int>[111, 222]));
      expect(
        kills.every((_RecordedKill k) => k.signal == ProcessSignal.sigkill),
        isTrue,
      );
    });

    test('on POSIX no-op when pgrep exits non-zero (no orphans)', () async {
      chromeReaperIsWindows = false;
      chromeReaperRunner = _stubRunner(<String, ProcessResult>{
        'pgrep -fl': ProcessResult(0, 1, '', ''),
      });
      bool killerCalled = false;
      chromeReaperKiller = (int pid, ProcessSignal signal) {
        killerCalled = true;
        return true;
      };

      await reapOrphans();

      expect(killerCalled, isFalse);
    });

    test('swallows individual SIGKILL failures and keeps iterating', () async {
      chromeReaperIsWindows = false;
      chromeReaperRunner = _stubRunner(<String, ProcessResult>{
        'pgrep -fl': ProcessResult(
          0,
          0,
          '111 flutter_tools_chrome_device A\n'
              '222 flutter_tools_chrome_device B\n'
              '333 flutter_tools_chrome_device C\n',
          '',
        ),
      });
      final List<int> attempts = <int>[];
      chromeReaperKiller = (int pid, ProcessSignal signal) {
        attempts.add(pid);
        if (pid == 222) throw const ProcessException('kill', <String>['-9']);
        return true;
      };

      await reapOrphans();

      // Despite 222 throwing, we still attempted 333 afterwards.
      expect(attempts, equals(<int>[111, 222, 333]));
    });
  });

  group('Windows fallback session guard', () {
    test('logs once across mixed function calls in the same session', () async {
      chromeReaperIsWindows = true;
      final List<String> logs = <String>[];
      chromeReaperLogger = logs.add;

      await captureChromePid(parentPid: 1);
      await captureChromeProfileDir(chromePid: 2);
      await killChromeAndProfile(chromePid: 3, tmpProfileDir: null);
      await reapOrphans();

      expect(logs.length, equals(1));
    });

    test('reset hook re-arms the once-per-session warning', () async {
      chromeReaperIsWindows = true;
      final List<String> logs = <String>[];
      chromeReaperLogger = logs.add;

      await reapOrphans();
      expect(logs.length, equals(1));

      chromeReaperResetWindowsWarningForTesting();

      await reapOrphans();
      expect(logs.length, equals(2));
    });
  });
}
