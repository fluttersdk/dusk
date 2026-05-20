import 'package:fluttersdk_artisan/artisan.dart';

import '../cdp/cdp_client.dart';
import '../cdp/device_presets.dart';

/// `artisan dusk:device --preset=<name>`: emulate a device profile
/// (viewport, DPR, touch events, user agent) in the running Chrome
/// instance via the Chrome DevTools Protocol.
///
/// Requires the app to have been launched with `artisan start --cdp-port=N`
/// so that the state file carries a valid [cdpPort] value.
///
/// Use `--list` to print all available preset names without connecting
/// to Chrome, and `--reset` to clear all emulation overrides.
final class DuskDeviceCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:device';

  @override
  String get description =>
      'Emulate a device profile (viewport + DPR + touch + user agent) via'
      ' Chrome DevTools Protocol.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'preset',
        help: 'Device preset name (e.g. iphone-x, pixel-5, ipad-pro-12.9,'
            ' desktop-1440). Use --list to see all.',
      )
      ..addFlag(
        'list',
        help: 'List all available device presets.',
        defaultsTo: false,
        negatable: false,
      )
      ..addFlag(
        'reset',
        help: 'Clear emulation (delegates to dusk:resize --reset semantics).',
        defaultsTo: false,
        negatable: false,
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. --list: no Chrome connection needed; print preset catalogue and exit.
    if (ctx.input.option('list') == true) {
      for (final name in presetNames) {
        final preset = kDevicePresets[name]!;
        ctx.output.writeln(
          '$name: ${preset.width}x${preset.height}'
          ' @ ${preset.deviceScaleFactor}x'
          ' (mobile=${preset.isMobile} touch=${preset.hasTouch})',
        );
      }
      return 0;
    }

    // 2. Read StateFile and confirm CDP is enabled.
    final state = await StateFile.read();
    final cdpPort = state?['cdpPort'] as int?;
    if (cdpPort == null) {
      ctx.output.error(
        'CDP not enabled. Run `artisan start --cdp-port=9222` first to'
        ' relaunch Chrome with a debug port.',
      );
      return 1;
    }

    // 3. Connect via CdpClient.
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
      // 4. --reset: clear all emulation overrides and return.
      if (ctx.input.option('reset') == true) {
        await client.send('Emulation.setUserAgentOverride', {'userAgent': ''});
        await client
            .send('Emulation.setTouchEmulationEnabled', {'enabled': false});
        await client.send('Emulation.clearDeviceMetricsOverride');
        // Resize OS window back to a sane desktop default.
        await _resizeChromeWindow(client, width: 1440, height: 900);
        ctx.output.success('Viewport emulation reset to defaults.');
        return 0;
      }

      // 5. Resolve preset by name.
      final presetInput = ctx.input.option('preset') as String?;
      final preset = presetInput != null ? lookupPreset(presetInput) : null;
      if (preset == null) {
        ctx.output.error(
          "Unknown preset '$presetInput'."
          ' Run dusk:device --list to see available.',
        );
        return 1;
      }

      // 6. Apply the full emulation chain: metrics -> optional touch -> UA.
      await client.send('Emulation.setDeviceMetricsOverride', {
        'width': preset.width,
        'height': preset.height,
        'deviceScaleFactor': preset.deviceScaleFactor,
        'mobile': preset.isMobile,
      });
      if (preset.hasTouch) {
        await client
            .send('Emulation.setTouchEmulationEnabled', {'enabled': true});
      }
      await client.send(
          'Emulation.setUserAgentOverride', {'userAgent': preset.userAgent});

      // 7. Resize the OS Chrome window to match the preset (plus macOS
      //    title-bar / URL-bar padding so the inner viewport equals the
      //    declared preset width/height).
      await _resizeChromeWindow(
        client,
        width: preset.width,
        height: preset.height + 130,
      );

      ctx.output.success(
        'Emulating $presetInput:'
        ' ${preset.width}x${preset.height}'
        ' @ ${preset.deviceScaleFactor}x.',
      );
      return 0;
    } on DuskCdpException catch (e) {
      ctx.output.error('CDP command failed: $e');
      return 1;
    } finally {
      // 8. Always close the CDP session.
      await client.close();
    }
  }

  /// Resizes the actual Chrome OS window via Browser.getWindowForTarget +
  /// Browser.setWindowBounds. `Emulation.setDeviceMetricsOverride` only
  /// changes the page's view of `window.innerWidth`; it does NOT shrink the
  /// OS window. Without this, mobile presets render inside a desktop-sized
  /// Chrome with empty space around the page.
  ///
  /// `Browser.*` is sessionless: callable on any WebSocket session. Failures
  /// surface as `DuskCdpException` to the outer catch.
  Future<void> _resizeChromeWindow(
    CdpClient client, {
    required int width,
    required int height,
  }) async {
    final Map<String, dynamic> window =
        await client.send('Browser.getWindowForTarget');
    final dynamic windowId = window['windowId'];
    if (windowId is! int) return;
    await client.send('Browser.setWindowBounds', {
      'windowId': windowId,
      'bounds': {
        'width': width,
        'height': height,
        'windowState': 'normal',
      },
    });
  }
}
