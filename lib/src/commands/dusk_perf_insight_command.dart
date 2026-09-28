import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `artisan dusk:perf_insight --id=I<n> [--token=perf-<n>] [--json]`: drill
/// into one insight of the report `dusk:perf_end` last produced. Routes
/// through `ext.dusk.perf_insight`.
class DuskPerfInsightCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:perf_insight';

  @override
  String get description =>
      'Drill into one insight of the last perf_end report: title, summary, '
      'the rows behind it, estimated savings and the next step.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption(
      'id',
      help: 'Insight id (e.g. I2) from the insights[] list dusk:perf_end '
          'returned.',
      mandatory: true,
    );
    parser.addOption(
      'token',
      help: 'sessionToken of that report. Optional: only the most recent '
          'closed session is kept, and a stale token is refused.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final String? id = ctx.input.option('id') as String?;
    if (id == null || id.isEmpty) {
      ctx.output.error(
        'Missing --id=<I1>. Run dusk:perf_end and pick an id from insights[].',
      );
      return 1;
    }
    final String? token = ctx.input.option('token') as String?;

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.perf_insight',
      <String, dynamic>{
        'id': id,
        if (token != null && token.isNotEmpty) 'token': token,
      },
    );
    reportFrameWarning(ctx, response);

    emitEnvelope(ctx, response, () {
      final Object? savings = response['estimatedSavingsMs'];
      ctx.output.success('${response['id']}: ${response['title']}');
      ctx.output.writeln('${response['summary']}');
      if (savings != null) {
        ctx.output.writeln('Estimated savings: ${savings}ms.');
      }
      ctx.output.writeln('Next: ${response['nextStep']}');
      ctx.output.writeln('Pass --json for the rows behind it.');
    });
    return 0;
  }
}
