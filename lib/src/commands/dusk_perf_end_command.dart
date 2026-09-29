import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `artisan dusk:perf_end [--json]`: close the measurement session opened by
/// `dusk:perf_begin` and print the report: a one-line summary naming the top
/// insight, or the bounded JSON report with `--json`. Routes through
/// `ext.dusk.perf_end`.
class DuskPerfEndCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:perf_end';

  @override
  String get description =>
      'Close the performance measurement session and report frames, ranked '
      'blocks, counters and insights.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.perf_end',
    );
    reportFrameWarning(ctx, response);

    // A refusal is a success envelope carrying `refused: true`, not an
    // error. Exiting 0 on it would let a shell caller chain on a report that
    // does not exist, which is the same failure `dusk:wait` had on a
    // timed-out condition.
    if (response['refused'] == true) {
      emitEnvelope(ctx, response, () {
        ctx.output.error(
          'Refused to report: ${response['reason']}',
        );
      });
      return 1;
    }

    emitEnvelope(ctx, response, () {
      ctx.output.success(_summaryLine(response));

      // The sentence above is what a human acts on, so the subset caveat has
      // to live beside it and not only in the JSON. Without this a session
      // that drew 4 frames and summarized 2 reads as a complete measurement,
      // and an empty ranking reads as "nothing was slow".
      final coverage = response['coverage'] as Map<String, dynamic>?;
      if (coverage != null && coverage['complete'] == false) {
        ctx.output.warning(
          'Partial: the engine drew ${coverage['framesDrawn']} frames and '
          '${coverage['framesSummarized']} were summarized, so this is a '
          'subset. An empty ranking here means "not reported", not '
          '"nothing was slow".',
        );
      }
    });
    return 0;
  }
}

/// One sentence over the report: frames, the budget verdict, and the insight
/// to open first. Insights arrive sorted by severity then savings, so the
/// first one is the one to name.
String _summaryLine(Map<String, dynamic> response) {
  final summary = response['summary'] as Map<String, dynamic>? ?? const {};
  final frames = summary['frames'] as Map<String, dynamic>? ?? const {};
  final buildMs = frames['buildMs'] as Map<String, dynamic>? ?? const {};
  final insights = (response['insights'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();

  final String head = 'Performance session ${response['sessionToken']} closed '
      '(${response['mode']}): ${frames['painted'] ?? 0} painted frames, '
      '${frames['overBudget'] ?? 0} over the ${summary['budgetMs']}ms budget, '
      'worst build ${buildMs['worst'] ?? 0}ms.';
  if (insights.isEmpty) {
    return '$head No insight fired. Pass --json for the report.';
  }

  final top = insights.first;
  return '$head ${insights.length} insights; top [${top['severity']}] '
      '${top['id']}: ${top['title']}. Drill in with dusk:perf_insight '
      '--id=${top['id']}, or pass --json for the report.';
}
