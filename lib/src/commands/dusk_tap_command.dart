import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:tap --ref=<eN>` — synthesize a tap on the element.
class DuskTapCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:tap';

  @override
  String get description => 'Tap a widget by ref token (from prior dusk:snap).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Snapshot ref token (e.g. e1).',
      mandatory: true,
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error(
        'Missing --ref=<eN>. Run dusk:snap first to obtain refs.',
      );
      return 1;
    }
    await ctx.callExtension<Map<String, dynamic>>('ext.dusk.tap', {'ref': ref});
    ctx.output.success('Tapped $ref');
    return 0;
  }
}
