import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `artisan dusk:wait_for_network_idle [--timeoutMs=<ms>] [--idleMs=<ms>]
/// [--pollIntervalMs=<ms>]` ; block until the running app reports zero
/// in-flight HTTP requests for a contiguous [idleMs] window.
///
/// Wraps the `ext.dusk.wait_for_network_idle` VM Service extension. The
/// Dart-side poll loop reads through `TelescopeStore.pendingHttpCount` when
/// `fluttersdk_telescope` is wired (host sets `pendingHttpCountReader`);
/// otherwise the count is constantly 0 and the call returns immediately
/// (missing-telescope graceful path).
class DuskWaitForNetworkIdleCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:wait_for_network_idle';

  @override
  String get description =>
      'Wait until the running app reports zero in-flight HTTP requests for '
      'a contiguous idleMs window.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption(
      'timeoutMs',
      help: 'Maximum total wait time in milliseconds (default 5000).',
      defaultsTo: '5000',
    );
    parser.addOption(
      'idleMs',
      help: 'Contiguous-zero window the loop must observe before declaring '
          'idle (default 500).',
      defaultsTo: '500',
    );
    parser.addOption(
      'pollIntervalMs',
      help: 'Poll cadence in milliseconds; minimum 100 (default 200).',
      defaultsTo: '200',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final timeoutMs = ctx.input.option('timeoutMs') as String?;
    final idleMs = ctx.input.option('idleMs') as String?;
    final pollIntervalMs = ctx.input.option('pollIntervalMs') as String?;

    final params = <String, dynamic>{};
    if (timeoutMs != null && timeoutMs.isNotEmpty) {
      params['timeoutMs'] = timeoutMs;
    }
    if (idleMs != null && idleMs.isNotEmpty) {
      params['idleMs'] = idleMs;
    }
    if (pollIntervalMs != null && pollIntervalMs.isNotEmpty) {
      params['pollIntervalMs'] = pollIntervalMs;
    }

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.wait_for_network_idle',
      params,
    );
    reportFrameWarning(ctx, response);

    // Same shape as ext.dusk.wait_for: a timeout comes back as a SUCCESS
    // envelope carrying `matched: false`, not as an error. Printing the
    // success line regardless made this pass on exactly the case it exists
    // to catch, and a CI script chains on the exit code.
    if (response['matched'] == false) {
      emitEnvelope(ctx, response, () {
        ctx.output.error(
          'Network did not go idle within the timeout. Requests were still '
          'in flight, so treat anything that depended on this wait as '
          'unproven.',
        );
      });
      return 1;
    }

    emitEnvelope(ctx, response, () => ctx.output.success('Network idle'));
    return 0;
  }
}
