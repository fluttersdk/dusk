import 'package:fluttersdk_artisan/artisan.dart';

import '../cdp/cdp_client.dart';

/// `artisan dusk:resize --width=<px> --height=<px>`: resize the running
/// Flutter web app viewport via Chrome DevTools Protocol Emulation methods.
///
/// Reads the CDP port from `~/.artisan/state.json` (written by
/// `artisan start --cdp-port=<port>`). Does not require a VM Service
/// connection; [CommandBoot.none] is correct.
final class DuskResizeCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:resize';

  @override
  String get description =>
      'Resize the running Flutter web app viewport via Chrome DevTools Protocol.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'width',
        help: 'Viewport width in CSS pixels (e.g. 375).',
        mandatory: true,
      )
      ..addOption(
        'height',
        help: 'Viewport height in CSS pixels (e.g. 812).',
        mandatory: true,
      )
      ..addOption(
        'dpr',
        help: 'Device pixel ratio (e.g. 3.0). Default 1.0; pass actual device '
            'DPR for Retina simulation.',
        defaultsTo: '1.0',
      )
      ..addFlag(
        'mobile',
        help:
            'Enable mobile device profile (touch + viewport meta + text autosizing).',
        defaultsTo: false,
      )
      ..addFlag(
        'touch',
        help: 'Enable touch event synthesis.',
        defaultsTo: false,
      )
      ..addFlag(
        'reset',
        help: 'Clear all emulation overrides (metrics + touch + user agent).',
        defaultsTo: false,
        negatable: false,
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Read StateFile; fail fast when cdpPort is absent.
    final Map<String, dynamic>? state = await StateFile.read();
    if (state == null || state['cdpPort'] == null) {
      ctx.output.error(
        'CDP not enabled. Run `artisan start --cdp-port=9222` first to '
        'relaunch Chrome with debug port.',
      );
      return 1;
    }

    final int cdpPort = state['cdpPort'] as int;

    // 2. Connect via CdpClient. Surface DuskCdpException as a user-facing
    //    error so the agent receives an actionable message.
    final CdpClient client;
    try {
      client = await CdpClient.connect(port: cdpPort);
    } on DuskCdpException catch (e) {
      ctx.output.error(
        'Failed to connect to Chrome CDP on port $cdpPort: $e',
      );
      return 1;
    }

    try {
      // 3. --reset path: clear all emulation overrides in the required order
      //    (user-agent first, touch second, metrics last).
      final bool isReset = (ctx.input.option('reset') as bool?) ?? false;
      if (isReset) {
        await client.send(
          'Emulation.setUserAgentOverride',
          <String, dynamic>{'userAgent': ''},
        );
        await client.send(
          'Emulation.setTouchEmulationEnabled',
          <String, dynamic>{'enabled': false},
        );
        await client.send('Emulation.clearDeviceMetricsOverride');
        ctx.output.success('Viewport reset to defaults.');
        return 0;
      }

      // 4. Normal resize path: parse flags, send setDeviceMetricsOverride and
      //    optionally setTouchEmulationEnabled.
      final int width =
          int.tryParse(ctx.input.option('width') as String? ?? '') ?? 0;
      final int height =
          int.tryParse(ctx.input.option('height') as String? ?? '') ?? 0;
      final double dpr =
          double.tryParse(ctx.input.option('dpr') as String? ?? '1.0') ?? 1.0;
      final bool mobile = (ctx.input.option('mobile') as bool?) ?? false;
      final bool touch = (ctx.input.option('touch') as bool?) ?? false;

      await client.send(
        'Emulation.setDeviceMetricsOverride',
        <String, dynamic>{
          'width': width,
          'height': height,
          'deviceScaleFactor': dpr,
          'mobile': mobile,
        },
      );

      if (touch) {
        await client.send(
          'Emulation.setTouchEmulationEnabled',
          <String, dynamic>{'enabled': true},
        );
      }

      ctx.output.success(
        'Viewport set to ${width}x$height @ ${dpr}x '
        '(mobile=$mobile touch=$touch).',
      );
      return 0;
    } on DuskCdpException catch (e) {
      ctx.output.error('CDP command failed: $e');
      return 1;
    } finally {
      // 5. Always close the CDP connection regardless of success or failure.
      await client.close();
    }
  }
}
