import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:screenshot --output=<path>` — capture a PNG/JPEG screenshot
/// of the running app and write it to disk.
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
    final output = ctx.input.option('output') as String?;
    final format = ctx.input.option('format') as String? ?? 'jpeg';
    final quality =
        int.tryParse(ctx.input.option('quality') as String? ?? '70') ?? 70;
    if (output == null || output.isEmpty) {
      ctx.output.error('Missing --output=<path>.');
      return 1;
    }
    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.screenshot',
      {'format': format, 'quality': quality},
    );
    final base64Str = result['base64'] as String?;
    if (base64Str == null) {
      ctx.output.error('Screenshot extension returned no base64: $result');
      return 1;
    }
    await File(output).writeAsBytes(base64Decode(base64Str));
    ctx.output.success('Wrote ${base64Str.length} base64 chars to $output');
    return 0;
  }
}
