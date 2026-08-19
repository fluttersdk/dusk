import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

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
    addJsonFlag(parser);
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

    final response = await ctx.callExtension<Map<String, dynamic>>(
        'ext.dusk.wait_for', params);
    reportFrameWarning(ctx, response);

    // A timed-out wait comes back as a SUCCESS envelope carrying
    // `matched: false`, not as an error. Printing the success line
    // regardless made the one command whose whole job is asserting a
    // post-condition pass on exactly the case it exists to catch, and
    // shell callers chain on its exit code.
    final bool matched = response['matched'] != false;
    if (!matched) {
      emitEnvelope(ctx, response, () {
        ctx.output.error(
          'Condition did not match within the timeout. Nothing on screen '
          'satisfied it, so treat any assertion that depended on this wait '
          'as unproven.',
        );
      });
      return 1;
    }

    emitEnvelope(ctx, response, () => ctx.output.success('Condition matched'));
    return 0;
  }
}
