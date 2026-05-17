import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:snap` — captures Semantics tree YAML from the running app.
class DuskSnapCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:snap';

  @override
  String get description =>
      'Capture Semantics tree YAML of the running Flutter app with [ref=eN] tokens.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('depth', help: 'Optional max tree depth.');
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final params = <String, dynamic>{};
    final depth = ctx.input.option('depth');
    if (depth != null) params['depth'] = depth;
    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.snap',
      params,
    );
    final snapshot = result['snapshot'] as String? ?? jsonEncode(result);
    ctx.output.writeln(snapshot);
    return 0;
  }
}
