import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

import '../cdp/cdp_client.dart';

/// `artisan dusk:screenshot --output=<path>` — capture a PNG/JPEG screenshot
/// of the running app and write it to disk.
///
/// On Flutter web targets (when `cdpPort` is present in state and neither
/// `--ref` nor `--rect` is supplied), the command routes through Chrome
/// DevTools Protocol `Page.captureScreenshot` to bypass the CanvasKit/DWDS
/// limitation that causes `RenderRepaintBoundary.toImage()` to hang (issue
/// #13). All other cases (native, or web with ref/rect) use the VM Service
/// extension `ext.dusk.screenshot`.
class DuskScreenshotCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:screenshot';

  @override
  String get description =>
      'Capture a screenshot of the running Flutter app to a file.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path.',
        mandatory: true,
      )
      ..addOption('format', defaultsTo: 'jpeg', allowed: ['jpeg', 'png'])
      ..addOption('quality', defaultsTo: '70', help: 'JPEG quality 1-100.');
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final String? output = ctx.input.option('output') as String?;
    final String format = ctx.input.option('format') as String? ?? 'jpeg';
    final int quality =
        int.tryParse(ctx.input.option('quality') as String? ?? '70') ?? 70;

    if (output == null || output.isEmpty) {
      ctx.output.error(
        'Missing --output=<path>. Example: '
        'dusk:screenshot --output=./shot.jpg --format=jpeg',
      );
      return 1;
    }

    // 1. Read StateFile to determine whether a CDP port is available.
    //    Defensively read ref/rect even though configure() does not declare them
    //    (MCP tools/call may supply them). If either is present, the CDP path
    //    is skipped — ref/rect on web intentionally falls through to the VM
    //    extension (documented limitation for v1).
    final Map<String, dynamic>? state = await StateFile.read();
    final Object? cdpPort = state?['cdpPort'];
    final Object? ref = ctx.input.option('ref');
    final Object? rect = ctx.input.option('rect');
    final bool hasRefOrRect = (ref != null && ref.toString().isNotEmpty) ||
        (rect != null && rect.toString().isNotEmpty);

    if (cdpPort != null && !hasRefOrRect) {
      return _handleCdpPath(ctx, cdpPort as int, output, format, quality);
    }

    // 2. Native path: call the VM Service extension and decode the base64
    //    response payload.
    return _handleNativePath(ctx, output, format, quality);
  }

  /// Captures a full-viewport screenshot via Chrome DevTools Protocol.
  ///
  /// Sends `Page.enable` then `Page.captureScreenshot`, decodes the `data`
  /// field, and writes the bytes to [output]. Surfaces [DuskCdpException] as
  /// a user-facing error with exit code 1.
  Future<int> _handleCdpPath(
    ArtisanContext ctx,
    int cdpPort,
    String output,
    String format,
    int quality,
  ) async {
    // 1. Connect via CdpClient. Surface DuskCdpException as a user-facing
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
      // 2. Enable the Page domain. Required by the CDP spec before
      //    captureScreenshot can be dispatched.
      await client.send('Page.enable');

      // 3. Capture the viewport. captureBeyondViewport is intentionally absent
      //    (defaults to false) to avoid a 2026 compositor-texture bug when
      //    combined with fromSurface=true.
      final Map<String, dynamic> result = await client.send(
        'Page.captureScreenshot',
        <String, dynamic>{
          'format': format,
          if (format == 'jpeg') 'quality': quality,
          'fromSurface': true,
        },
      );

      // 4. Decode and write bytes.
      final List<int> bytes = base64Decode(result['data'] as String);
      await File(output).writeAsBytes(bytes);
      final String kb = (bytes.length / 1024).toStringAsFixed(1);
      ctx.output.success(
        'Wrote ${bytes.length} bytes ($kb KB, $format) to $output',
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

  /// Calls the VM Service extension `ext.dusk.screenshot` and writes the
  /// decoded base64 bytes to [output].
  Future<int> _handleNativePath(
    ArtisanContext ctx,
    String output,
    String format,
    int quality,
  ) async {
    final Map<String, dynamic> result =
        await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.screenshot',
      {'format': format, 'quality': quality},
    );
    final String? base64Str = result['base64'] as String?;
    if (base64Str == null) {
      ctx.output.error('Screenshot extension returned no base64: $result');
      return 1;
    }
    final List<int> bytes = base64Decode(base64Str);
    await File(output).writeAsBytes(bytes);
    final String kb = (bytes.length / 1024).toStringAsFixed(1);
    ctx.output
        .success('Wrote ${bytes.length} bytes ($kb KB, $format) to $output');
    return 0;
  }
}
