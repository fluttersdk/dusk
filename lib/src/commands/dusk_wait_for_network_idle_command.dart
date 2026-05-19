import 'package:fluttersdk_artisan/artisan.dart';

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

    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.wait_for_network_idle',
      params,
    );
    ctx.output.success('Network idle');
    return 0;
  }
}
