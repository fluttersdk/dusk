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
      //
      // CLI passes options as strings via ArgParser, but MCP `tools/call`
      // dispatches typed JSON (`width: 390` as int, `mobile: true` as bool).
      // Accept both via runtime type sniffing so the same command surface
      // works from both surfaces without per-route casts at the boundary.
      final int width = _readInt(ctx.input.option('width'));
      final int height = _readInt(ctx.input.option('height'));
      final double dpr = _readDouble(ctx.input.option('dpr'), fallback: 1.0);
      final bool mobile = _readBool(ctx.input.option('mobile'));
      final bool touch = _readBool(ctx.input.option('touch'));

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

  /// Reads an `int` from a value that may arrive as an `int` (MCP `tools/call`
  /// JSON), a numeric `String` (ArgParser CLI), or `null` / empty.
  int _readInt(Object? raw, {int fallback = 0}) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? fallback;
    return fallback;
  }

  /// Reads a `double` from a value that may arrive as a `num` (MCP) or a
  /// numeric `String` (CLI).
  double _readDouble(Object? raw, {double fallback = 1.0}) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? fallback;
    return fallback;
  }

  /// Reads a `bool` from a value that may arrive as `bool` (MCP / ArgParser
  /// flag) or `String` (legacy stringified flag).
  bool _readBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() == 'true' || raw == '1';
    return false;
  }
}
