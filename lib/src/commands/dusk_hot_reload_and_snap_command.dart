import 'dart:convert';

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

/// Default [HotReloadFn]: fires `vm.reloadSources(force: true)` against the
/// running app's main isolate. `force: true` matches mcp_flutter's
/// implementation: an idempotent re-import even when no source has changed
/// guarantees the post-reload `reassemble` rebuilds the widget tree (so a
/// caller running the tool a second time still sees a fresh snapshot).
Future<HotReloadResult> _defaultReload(ArtisanContext ctx) async {
  final client = ctx.vmClient;
  if (client == null) {
    return const HotReloadResult(
      success: false,
      error: 'No VM Service client; run `artisan start` first.',
    );
  }
  try {
    final isolateId = await client.getMainIsolateId();
    final report = await client.reloadSources(isolateId, force: true);
    final bool success = report.success ?? false;
    return HotReloadResult(
      success: success,
      error: success ? null : 'Hot reload reported success=false',
    );
  } catch (e) {
    return HotReloadResult(success: false, error: e.toString());
  }
}
