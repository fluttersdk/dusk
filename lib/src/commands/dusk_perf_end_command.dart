import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `artisan dusk:perf_end [--json]`: close the measurement session opened by
/// `dusk:perf_begin` and print the attribution report. Routes through
/// `ext.dusk.perf_end`.
class DuskPerfEndCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:perf_end';

  @override
  String get description =>
      'Close the performance measurement session and report the frame, block, '
      'wind and magic attribution.';

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
      final summary = response['frameSummary'] as Map<String, dynamic>?;
      final frameCount = summary?['frame_count'] ?? 0;
      final worstBuild = summary?['worst_frame_build_time_millis'] ?? 0;
      ctx.output.success(
        'Performance session closed: $frameCount frames, worst build '
        '${worstBuild}ms. Pass --json for the full attribution.',
      );

      // The sentence above is what a human acts on, so the subset caveat has
      // to live beside it and not only in the JSON. Without this a session
      // that drew 4 frames and summarized 2 reads as a complete measurement,
      // and an empty attribution reads as "nothing was slow".
      final coverage = response['coverage'] as Map<String, dynamic>?;
      if (coverage != null && coverage['complete'] == false) {
        ctx.output.warning(
          'Partial: the engine drew ${coverage['framesDrawn']} frames and '
          '${coverage['framesSummarized']} were summarized, so this is a '
          'subset. An empty attribution here means "not reported", not '
          '"nothing was slow".',
        );
      }
    });
    return 0;
  }
}
