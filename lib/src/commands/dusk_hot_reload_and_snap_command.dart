import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:meta/meta.dart';

/// Outcome of a single hot reload attempt, decoupled from the
/// `package:vm_service` `ReloadReport` shape so tests can inject fakes
/// without dragging the VM Service library into the test surface.
@immutable
class HotReloadResult {
  /// Builds an immutable result. [success] is mandatory; [error] is
  /// populated only on the compile-error path and surfaces to the caller as
  /// the `error` field on the response envelope.
  const HotReloadResult({
    required this.success,
    this.error,
  });

  /// Whether the VM accepted the reload. Maps to `ReloadReport.success`.
  final bool success;

  /// Compile error or hard failure message. Null on success.
  final String? error;
}

/// Function signature for the reload trigger. The CLI command resolves this
/// against `ctx.vmClient!.reloadSources(...)` by default; tests inject a
/// fake that returns a [HotReloadResult] without dialing a real VM Service.
typedef HotReloadFn = Future<HotReloadResult> Function(ArtisanContext ctx);

/// `artisan dusk:hot_reload_and_snap [--no-screenshot]` — fused round-trip
/// that triggers a hot reload, waits for completion, captures the
/// post-reload Semantics snapshot + screenshot + recent exceptions, and
/// bundles everything into a single MCP-friendly response.
///
/// Architectural decision (mcp_flutter's `fmt_hot_reload_and_capture`
/// pattern): the hot reload trigger lives CLI-side, NOT inside a VM Service
/// extension. The dusk extension handler runs INSIDE the running isolate,
/// so it cannot reload itself: the handler would block on the reload and
/// the request would never return. The CLI command orchestrates instead,
/// using [VmServiceClient.reloadSources] from
/// [package:fluttersdk_artisan/vm/vm_service_client.dart] to fire the
/// reload, then calling the existing `ext.dusk.snap` /
/// `ext.dusk.screenshot` / `ext.dusk.exceptions` extensions for the
/// post-reload pieces.
///
/// Response envelope on success:
/// ```json
/// {
///   "reloaded": true,
///   "durationMs": 245,
///   "snapshot": "<yaml>",
///   "screenshot": "<base64>",
///   "recentExceptions": []
/// }
/// ```
///
/// Response envelope on compile error (snap + screenshot skipped):
/// ```json
/// {
///   "reloaded": false,
///   "durationMs": 87,
///   "error": "lib/main.dart:5:1: Error: expected ';'",
///   "recentExceptions": []
/// }
/// ```
///
/// Response envelope when the screenshot capture itself fails (snap
/// succeeded; partial result rather than bailing the whole round-trip):
/// ```json
/// {
///   "reloaded": true,
///   "durationMs": 245,
///   "snapshot": "<yaml>",
///   "screenshotError": "ext.dusk.screenshot failed: <msg>",
///   "recentExceptions": []
/// }
/// ```
class DuskHotReloadAndSnapCommand extends ArtisanCommand {
  /// Builds the command with an optional [reloadFn] override. Production
  /// code constructs the command with no arguments; tests inject a fake
  /// reloadFn so the command can be exercised without a live VM Service.
  DuskHotReloadAndSnapCommand({HotReloadFn? reloadFn})
      : _reloadFn = reloadFn ?? _defaultReload;

  final HotReloadFn _reloadFn;

  /// The most recent invocation's response envelope. Set every time
  /// [handle] runs; exposed so callers (and tests) can read the structured
  /// payload without parsing the formatted CLI output.
  Map<String, dynamic>? lastResult;

  @override
  String get name => 'dusk:hot_reload_and_snap';

  @override
  String get description =>
      'Hot reload the running app, then capture snapshot + screenshot + '
      'recent exceptions in a single round-trip.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addFlag(
      'screenshot',
      help: 'Capture a screenshot after the reload (default true). Pass '
          '`--no-screenshot` to skip the screenshot step entirely.',
      defaultsTo: true,
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final bool captureScreenshot =
        (ctx.input.option('screenshot') as bool?) ?? true;

    // 1. Trigger the hot reload through the injected function-pointer.
    //    Wrap with a stopwatch so the response carries a positive
    //    `durationMs` regardless of whether the reload succeeded.
    final Stopwatch sw = Stopwatch()..start();
    final HotReloadResult reload = await _reloadFn(ctx);
    sw.stop();
    final int durationMs = sw.elapsedMilliseconds;

    // 2. On failure: skip snap + screenshot but still gather exceptions so
    //    the agent has post-reload diagnostics. Return the failure envelope.
    if (!reload.success) {
      final List<dynamic> exceptions = await _safeExceptions(ctx);
      final result = <String, dynamic>{
        'reloaded': false,
        'durationMs': durationMs,
        'error': reload.error ?? 'hot reload failed',
        'recentExceptions': exceptions,
      };
      lastResult = result;
      ctx.output.writeln(jsonEncode(result));
      return 0;
    }

    // 3. Success: capture the post-reload snapshot. Snap failure aborts the
    //    round-trip because there is nothing useful to return without it.
    final Map<String, dynamic> snap =
        await ctx.callExtension<Map<String, dynamic>>('ext.dusk.snap');
    final String snapshot = snap['snapshot'] as String? ?? jsonEncode(snap);

    // 4. Capture the screenshot when requested. Screenshot failure does NOT
    //    abort the round-trip: dusk_observe + the agent can still act on
    //    the snapshot alone, so surface the error as `screenshotError`
    //    instead of bailing the whole call.
    String? screenshotPayload;
    String? screenshotError;
    if (captureScreenshot) {
      try {
        final Map<String, dynamic> shot = await ctx
            .callExtension<Map<String, dynamic>>('ext.dusk.screenshot');
        screenshotPayload = shot['base64'] as String?;
      } catch (e) {
        screenshotError = 'ext.dusk.screenshot failed: $e';
      }
    }

    // 5. Recent exceptions: always best-effort, missing-telescope graceful.
    final List<dynamic> exceptions = await _safeExceptions(ctx);

    // 6. Build the success envelope.
    final result = <String, dynamic>{
      'reloaded': true,
      'durationMs': durationMs,
      'snapshot': snapshot,
      'recentExceptions': exceptions,
    };
    if (!captureScreenshot) {
      result['screenshot'] = null;
    } else if (screenshotPayload != null) {
      result['screenshot'] = screenshotPayload;
    } else if (screenshotError != null) {
      result['screenshotError'] = screenshotError;
    }

    lastResult = result;
    ctx.output.writeln(jsonEncode(result));
    return 0;
  }

  /// Best-effort exception read. Telescope absence is reported as an empty
  /// list (the handler's missing-telescope graceful path); any
  /// transport-level failure also collapses to an empty list so the main
  /// payload always lands.
  Future<List<dynamic>> _safeExceptions(ArtisanContext ctx) async {
    try {
      final Map<String, dynamic> resp =
          await ctx.callExtension<Map<String, dynamic>>('ext.dusk.exceptions');
      final List<dynamic>? list = resp['exceptions'] as List<dynamic>?;
      return list ?? const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }
}

/// Default [HotReloadFn]: drives `flutter run`'s own keystroke protocol by
/// writing `r\n` to the stdin FIFO recorded in `~/.artisan/state.json`, then
/// waits for the VM Service `IsolateReload` event so the post-reload widget
/// tree is settled before the snapshot capture runs.
///
/// Direct `vm.reloadSources` is intentionally avoided: when `flutter run` is
/// mediating (the normal case for `artisan start`), the Flutter Tool watches
/// the file system and owns the reload pipeline; a raw VM Service reload
/// from a sibling process is rejected with `success=false` and produces no
/// reassemble. The keystroke path is the same one `reload` uses and works
/// uniformly across web/desktop/mobile targets.
Future<HotReloadResult> _defaultReload(ArtisanContext ctx) async {
  final Map<String, dynamic>? state = await StateFile.read();
  if (state == null) {
    return const HotReloadResult(
      success: false,
      error: 'No artisan state file; run `artisan start` first.',
    );
  }
  final String? pipePath = state['stdinPipe'] as String?;
  if (pipePath == null) {
    return const HotReloadResult(
      success: false,
      error:
          'state.json has no stdinPipe entry; restart the app via `artisan restart`.',
    );
  }
  if (!File(pipePath).existsSync()) {
    return HotReloadResult(
      success: false,
      error: 'flutter run stdin pipe missing at $pipePath',
    );
  }

  // Discover the flutter run log path so we can tail-poll for the
  // "Reloaded N libraries in Mms" marker that flutter_tools emits once a
  // reload finishes (compile + reassemble both done). The VM Service
  // `IsolateReload` event would be cleaner but does NOT fire on no-op
  // reloads (0 libraries changed) — and `hot_reload_and_snap` is most
  // useful precisely when the caller wants to FORCE a reassemble without
  // editing files.
  final String? logPath = state['logPath'] as String? ??
      state['log'] as String? ??
      _defaultLogPath();
  final File logFile = logPath == null ? File('') : File(logPath);
  final int baselineLogLength = logFile.existsSync() ? logFile.lengthSync() : 0;

  try {
    // 1. Push `r\n` through `printf %s > fifo`. Dart's File.open() calls
    //    lseek which FIFOs reject; the shell write opens-writes-closes
    //    without seeking, matching the canonical reload command.
    final ProcessResult write = await Process.run('sh', <String>[
      '-c',
      "printf 'r\\n' > ${_shellQuote(pipePath)}",
    ]);
    if (write.exitCode != 0) {
      return HotReloadResult(
        success: false,
        error:
            'Failed to write to flutter run stdin pipe (exit ${write.exitCode}): '
            '${write.stderr}',
      );
    }

    // 2. Poll the log for a "Reloaded N libraries" line that appears after
    //    [baselineLogLength]. flutter_tools always emits this line on a
    //    successful reload (even when N==0); a compile error emits
    //    "Try again after fixing the above error(s)." instead.
    final RegExp successMarker =
        RegExp(r'Reloaded \d+( of \d+)? librar(y|ies) in \d+ms');
    final RegExp failureMarker =
        RegExp(r'Try again after fixing the above error');
    final Stopwatch deadline = Stopwatch()..start();
    const Duration timeout = Duration(seconds: 10);
    while (deadline.elapsed < timeout) {
      if (logFile.existsSync()) {
        final String tail = await _readLogTail(logFile, baselineLogLength);
        if (failureMarker.hasMatch(tail)) {
          return HotReloadResult(
            success: false,
            error: 'Hot reload reported a compile error; see flutter run log.',
          );
        }
        if (successMarker.hasMatch(tail)) {
          // Reassemble runs synchronously inside the same flutter_tools
          // tick that emits the marker, so the next frame is already the
          // post-reload tree.
          return const HotReloadResult(success: true);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return const HotReloadResult(
      success: false,
      error: 'Hot reload did not signal completion in time',
    );
  } catch (e) {
    return HotReloadResult(success: false, error: e.toString());
  }
}

/// Resolve the canonical flutter run log path (`~/.artisan/flutter-dev.log`)
/// in the same shape `start` writes it.
String? _defaultLogPath() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return null;
  return '$home/.artisan/flutter-dev.log';
}

/// Read the slice of [file] that lives past [baseline] bytes. Returns an
/// empty string when the slice is empty or the file shrank (log rotation).
Future<String> _readLogTail(File file, int baseline) async {
  final int end = file.lengthSync();
  if (end <= baseline) return '';
  final RandomAccessFile raf = await file.open();
  try {
    await raf.setPosition(baseline);
    final List<int> bytes = await raf.read(end - baseline);
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    await raf.close();
  }
}

String _shellQuote(String s) {
  if (RegExp(r'^[A-Za-z0-9_./=:-]+$').hasMatch(s)) return s;
  return "'${s.replaceAll("'", r"'\''")}'";
}
