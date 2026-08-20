import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

import '../cdp/cdp_client.dart';
import 'frame_warning_output.dart';

/// `artisan dusk:screenshot --output=<path>` — capture a PNG/JPEG screenshot
/// of the running app and write it to disk.
///
/// Captures the full app frame. On Flutter web targets (when `cdpPort` is
/// present in state) the command routes through Chrome DevTools Protocol
/// `Page.captureScreenshot` to bypass the CanvasKit/DWDS limitation that
/// causes `RenderRepaintBoundary.toImage()` to hang (issue #13). Native
/// targets use the VM Service extension `ext.dusk.screenshot`.
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
      ..addOption('quality', defaultsTo: '70', help: 'JPEG quality 1-100.')
      ..addOption(
        'ref',
        help: 'Capture only this widget (an e<N> or q<N> token from '
            'dusk:snap / dusk:find). Omit for the whole viewport.',
      )
      ..addOption(
        'rect',
        help: 'Sub-rect "x,y,w,h" in logical pixels, relative to the ref\'s '
            'top-left. Requires --ref.',
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final String? output = ctx.input.option('output') as String?;
    final String format = ctx.input.option('format') as String? ?? 'jpeg';
    final int quality =
        int.tryParse(ctx.input.option('quality') as String? ?? '70') ?? 70;
    final String? rawRef = ctx.input.option('ref') as String?;
    final String? ref = (rawRef != null && rawRef.isNotEmpty) ? rawRef : null;
    final String? rawRect = ctx.input.option('rect') as String?;
    final String? rect =
        (rawRect != null && rawRect.isNotEmpty) ? rawRect : null;

    if (output == null || output.isEmpty) {
      ctx.output.error(
        'Missing --output=<path>. Example: '
        'dusk:screenshot --output=./shot.jpg --format=jpeg',
      );
      return 1;
    }

    if (rect != null && ref == null) {
      ctx.output.error(
        '--rect is relative to a widget, so it needs --ref. Omit both to '
        'capture the whole viewport.',
      );
      return 1;
    }

    // 1. Read StateFile to determine whether a CDP port is available. A
    //    present cdpPort means a web target where the in-isolate toImage()
    //    path hangs under CanvasKit+DWDS; capture over CDP instead.
    final Map<String, dynamic>? state = await StateFile.read();
    final int? cdpPort = _readCdpPort(state?['cdpPort']);

    if (cdpPort != null) {
      return _handleCdpPath(ctx, cdpPort, output, format, quality, ref, rect);
    }

    // 2. Native path: call the VM Service extension and decode the base64
    //    response payload.
    return _handleNativePath(ctx, output, format, quality, ref, rect);
  }

  /// Captures a screenshot via Chrome DevTools Protocol.
  ///
  /// Sends `Page.enable` then `Page.captureScreenshot`, decodes the `data`
  /// field, and writes the bytes to [output]. Surfaces [DuskCdpException] as
  /// a user-facing error with exit code 1.
  ///
  /// With [ref] set the capture is clipped to that widget. CDP has no notion
  /// of a Flutter ref, so the region is resolved first through the geometry
  /// mode of `ext.dusk.screenshot`, which returns the rect without
  /// rasterising (the rasterise is exactly what hangs on this target). One
  /// extra round-trip, and no second source of truth for what a ref covers.
  Future<int> _handleCdpPath(
    ArtisanContext ctx,
    int cdpPort,
    String output,
    String format,
    int quality,
    String? ref,
    String? rect,
  ) async {
    // 0. Resolve the clip before opening the CDP connection: a ref that no
    //    longer resolves is a caller error, and failing here keeps the error
    //    message about the ref rather than about Chrome.
    Map<String, dynamic>? clip;
    if (ref != null) {
      clip = await _resolveClip(ctx, ref, rect);
      if (clip == null) return 1;
    }

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

      // 3. Capture. captureBeyondViewport is intentionally absent (defaults
      //    to false) to avoid a 2026 compositor-texture bug when combined
      //    with fromSurface=true.
      final Map<String, dynamic> result = await client.send(
        'Page.captureScreenshot',
        <String, dynamic>{
          'format': format,
          if (format == 'jpeg') 'quality': quality,
          'fromSurface': true,
          if (clip != null) 'clip': clip,
        },
      );

      // 4. Validate the payload, then decode and write bytes. A malformed CDP
      //    response (missing `data`, error shape) returns a clear error rather
      //    than throwing an uncaught cast exception.
      final Object? data = result['data'];
      if (data is! String) {
        ctx.output.error(
          'CDP Page.captureScreenshot returned no image data: $result',
        );
        return 1;
      }
      final List<int> bytes = base64Decode(data);
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

  /// Resolves the CDP `clip` for [ref] (optionally narrowed by [rect]).
  ///
  /// Returns null after printing an error when the ref carries no live rect,
  /// which is a hard stop rather than a fallback: silently capturing the
  /// whole viewport would hand the caller an image that looks right and
  /// answers a different question, and that is the failure mode `--ref`
  /// exists to remove.
  ///
  /// Flutter logical pixels and CDP CSS pixels are the same unit, so the
  /// rect crosses over unscaled and `scale: 1` keeps the output at the
  /// page's own device pixel ratio.
  Future<Map<String, dynamic>?> _resolveClip(
    ArtisanContext ctx,
    String ref,
    String? rect,
  ) async {
    final Map<String, dynamic> geometry =
        await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.screenshot',
      <String, dynamic>{
        'ref': ref,
        if (rect != null) 'rect': rect,
        'geometry': 'true',
      },
    );
    reportFrameWarning(ctx, geometry);

    final Object? raw = geometry['rect'];
    if (raw is! Map) {
      ctx.output.error(
        'Cannot clip to ref "$ref": the extension returned no rect for it. '
        'Re-run dusk:snap and use a ref from that snapshot.',
      );
      return null;
    }

    final Map<String, dynamic> resolved = raw.cast<String, dynamic>();
    return <String, dynamic>{
      'x': resolved['x'],
      'y': resolved['y'],
      'width': resolved['width'],
      'height': resolved['height'],
      'scale': 1,
    };
  }

  /// Reads `cdpPort` from the state map, tolerating `int`, `num`, or numeric
  /// `String` shapes. Returns null when absent or unparseable, so a corrupt or
  /// cross-version state file falls back to the native VM-extension path
  /// instead of throwing on a force-cast.
  int? _readCdpPort(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  /// Calls the VM Service extension `ext.dusk.screenshot` and writes the
  /// decoded base64 bytes to [output].
  Future<int> _handleNativePath(
    ArtisanContext ctx,
    String output,
    String format,
    int quality,
    String? ref,
    String? rect,
  ) async {
    final Map<String, dynamic> result =
        await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.screenshot',
      <String, dynamic>{
        'format': format,
        'quality': quality,
        if (ref != null) 'ref': ref,
        if (rect != null) 'rect': rect,
      },
    );
    reportFrameWarning(ctx, result);
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
