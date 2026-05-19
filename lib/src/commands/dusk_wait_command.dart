import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:wait [--text=<s>] [--textGone=<s>] [--expression=<dart>]
/// [--timeoutMs=<ms>]` — wait for a condition in the running app.
class DuskWaitCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:wait';

  @override
  String get description =>
      'Wait for a text, text-gone, or expression condition in the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'text',
      help: 'Wait until this text appears in the widget tree.',
    );
    parser.addOption(
      'textGone',
      help: 'Wait until this text disappears from the widget tree.',
    );
    parser.addOption(
      'expression',
      help: 'Wait until this Dart expression evaluates to true.',
    );
    parser.addOption(
      'timeoutMs',
      help: 'Maximum wait time in milliseconds.',
      defaultsTo: '5000',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final text = ctx.input.option('text') as String?;
    final textGone = ctx.input.option('textGone') as String?;
    final expression = ctx.input.option('expression') as String?;
    final timeoutMs = ctx.input.option('timeoutMs') as String?;

    final hasCondition = (text != null && text.isNotEmpty) ||
        (textGone != null && textGone.isNotEmpty) ||
        (expression != null && expression.isNotEmpty);

    if (!hasCondition) {
      ctx.output.error(
        'Provide at least one condition: --text, --textGone, or --expression.',
      );
      return 1;
    }

    final params = <String, dynamic>{};
    if (text != null && text.isNotEmpty) params['text'] = text;
    if (textGone != null && textGone.isNotEmpty) params['textGone'] = textGone;
    if (expression != null && expression.isNotEmpty) {
      params['expression'] = expression;
    }
    if (timeoutMs != null && timeoutMs.isNotEmpty) {
      params['timeoutMs'] = timeoutMs;
    }

    await ctx.callExtension<Map<String, dynamic>>('ext.dusk.wait_for', params);
    ctx.output.success('Condition matched');
    return 0;
  }
}
