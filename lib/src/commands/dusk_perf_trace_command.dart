import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:perf_trace --out=<file> [--token=perf-<n>]`: write the last
/// closed perf session's timeline as a Chrome Trace JSON file and print only
/// its path. Routes through `ext.dusk.perf_trace`.
///
/// A trace runs to thousands of events, which is the wrong thing to put in
/// an agent's context: the file opens in ui.perfetto.dev or chrome://tracing,
/// and the path is all the caller needs to hand on.
class DuskPerfTraceCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:perf_trace';

  @override
  String get description =>
      'Write the last closed perf session as a Chrome Trace JSON file '
      '(ui.perfetto.dev, chrome://tracing) and print its path.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'out',
        help: 'File to write, e.g. build/perf/trace.json. Parent directories '
            'are created.',
      )
      ..addOption(
        'token',
        help: 'sessionToken of the session to export. Optional: only the '
            'most recent closed session is kept, and a stale token is '
            'refused.',
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Validate before touching the app.
    final String? out = ctx.input.option('out') as String?;
    if (out == null || out.isEmpty) {
      ctx.output.error(
        'Missing --out=<file>: the trace is written to a file, not printed.',
      );
      return 1;
    }
    final String? token = ctx.input.option('token') as String?;

    // 2. Export. A refusal from the extension (no closed session, a stale
    //    token, a session still open) surfaces as the extension's error.
    final Map<String, dynamic> response =
        await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.perf_trace',
      <String, dynamic>{
        if (token != null && token.isNotEmpty) 'token': token,
      },
    );

    // 3. Keep the Trace Event object format only: the envelope's
    //    sessionToken already sits in otherData.
    final File file = File(out).absolute;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'traceEvents': response['traceEvents'],
        'displayTimeUnit': response['displayTimeUnit'],
        'otherData': response['otherData'],
      }),
    );
    ctx.output.writeln(file.path);
    return 0;
  }
}
