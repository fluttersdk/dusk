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
    parser.addOption(
      'startRef',
      help: 'Ref token of the drag source widget (e.g. e1).',
      mandatory: true,
    );
    parser.addOption(
      'endRef',
      help: 'Ref token of the drag target widget (e.g. e2).',
      mandatory: true,
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final startRef = ctx.input.option('startRef') as String?;
    if (startRef == null || startRef.isEmpty) {
      ctx.output.error(
        'Missing --startRef=<eN>. Run dusk:snap first to obtain refs.',
      );
      return 1;
    }

    final endRef = ctx.input.option('endRef') as String?;
    if (endRef == null || endRef.isEmpty) {
      ctx.output.error(
        'Missing --endRef=<eN>. Run dusk:snap first to obtain refs.',
      );
      return 1;
    }

    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.drag',
      {'startRef': startRef, 'endRef': endRef},
    );
    ctx.output.success('Dragged $startRef to $endRef');
    return 0;
  }
}
