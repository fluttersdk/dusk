import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:drag --startRef=<eN> --endRef=<eN>` — drag from one widget to another.
class DuskDragCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:drag';

  @override
  String get description =>
      'Drag from one widget to another using ref tokens from a prior dusk:snap.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    // Primary flags: --fromRef / --toRef (parallel to other gesture commands'
    // --ref convention; "from"/"to" reads cleaner than "start"/"end" for a
    // drag). Legacy --startRef / --endRef stay supported as aliases for
    // backwards compat with anyone who scripted against the original shape.
    parser.addOption('fromRef',
        help: 'Ref token of the drag source widget (e.g. e1).');
    parser.addOption('toRef',
        help: 'Ref token of the drag target widget (e.g. e2).');
    parser.addOption('startRef',
        help: 'Alias for --fromRef (legacy; retained for back-compat).');
    parser.addOption('endRef',
        help: 'Alias for --toRef (legacy; retained for back-compat).');
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-drag snapshot in the response.',
        defaultsTo: false);
    parser.addFlag('checkStable',
        help: 'Run the Stable actionability gate.', defaultsTo: true);
    parser.addFlag('checkReceivesEvents',
        help: 'Run the Receives-Events actionability gate.', defaultsTo: true);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // Accept --fromRef OR --startRef (and same for --toRef / --endRef);
    // prefer the new --fromRef/--toRef when both are supplied.
    final startRef = (ctx.input.option('fromRef') as String?) ??
        (ctx.input.option('startRef') as String?);
    if (startRef == null || startRef.isEmpty) {
      ctx.output.error(
          'Missing --fromRef=<eN> (alias --startRef). Run dusk:snap first to obtain refs.');
      return 1;
    }
    final endRef = (ctx.input.option('toRef') as String?) ??
        (ctx.input.option('endRef') as String?);
    if (endRef == null || endRef.isEmpty) {
      ctx.output.error(
          'Missing --toRef=<eN> (alias --endRef). Run dusk:snap first to obtain refs.');
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.drag',
      {
        'startRef': startRef,
        'endRef': endRef,
        'includeSnapshot': includeSnapshot.toString(),
        'checkStable': checkStable.toString(),
        'checkReceivesEvents': checkReceivesEvents.toString(),
      },
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Dragged $startRef to $endRef');
    }
    return 0;
  }
}
