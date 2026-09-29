import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `artisan dusk:perf_begin [--mode=attribution|timing] [--phases]`: open a
/// performance measurement session in the running app. Routes through
/// `ext.dusk.perf_begin`.
class DuskPerfBeginCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:perf_begin';

  @override
  String get description =>
      'Open a performance measurement session: zero the frame, wind and '
      'magic counters and, in attribution mode, switch on build profiling.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption(
      'mode',
      help: 'attribution switches build profiling on for blocks and counters; '
          'timing touches no profiling flag and reports frame timings only, '
          'the pass whose milliseconds are worth comparing.',
      allowed: <String>['attribution', 'timing'],
      defaultsTo: 'attribution',
    );
    parser.addFlag(
      'phases',
      help: 'Also profile layout and paint, not just builds. Phase detail '
          'multiplies the span volume, so it is off by default.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final bool phases = (ctx.input.option('phases') as bool?) ?? false;
    final String mode = (ctx.input.option('mode') as String?) ?? 'attribution';

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.perf_begin',
      <String, dynamic>{
        'mode': mode,
        'phases': phases.toString(),
      },
    );
    reportFrameWarning(ctx, response);

    emitEnvelope(ctx, response, () {
      final String token = response['sessionToken']?.toString() ?? 'unknown';
      final String scope = mode == 'timing'
          ? 'timing: frame timings only'
          : phases
              ? 'attribution: builds + layout + paint'
              : 'attribution: builds';
      ctx.output.success(
        'Performance session $token open ($scope). Drive the interaction, '
        'then run dusk:perf_end.',
      );
    });
    return 0;
  }
}
