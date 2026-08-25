import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `artisan dusk:perf_begin [--phases]`: open a performance measurement
/// session in the running app. Routes through `ext.dusk.perf_begin`.
class DuskPerfBeginCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:perf_begin';

  @override
  String get description =>
      'Open a performance measurement session: switch on Flutter build '
      'profiling and zero the frame, wind and magic counters.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
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

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.perf_begin',
      <String, dynamic>{'phases': phases.toString()},
    );
    reportFrameWarning(ctx, response);

    emitEnvelope(ctx, response, () {
      final String token = response['sessionToken']?.toString() ?? 'unknown';
      ctx.output.success(
        'Performance session $token open'
        '${phases ? ' (builds + layout + paint)' : ' (builds)'}. Drive the '
        'interaction, then run dusk:perf_end.',
      );
    });
    return 0;
  }
}
