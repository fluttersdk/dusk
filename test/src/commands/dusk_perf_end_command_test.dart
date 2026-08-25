import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_end_command.dart';

/// Stubs [ArtisanContext.callExtension] so the test never hits a real VM
/// Service.
class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
    required Map<String, dynamic> response,
  })  : _response = response,
        super.bare(input, output);

  final Map<String, dynamic> _response;

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    return _response as T;
  }
}

Map<String, dynamic> _report({
  required int framesDrawn,
  required int framesSummarized,
}) {
  final bool complete = framesSummarized >= framesDrawn;
  return <String, dynamic>{
    'sessionToken': 'perf-1',
    'refused': false,
    'phases': true,
    'liveness': <String, dynamic>{
      'baseline': 0,
      'final': framesDrawn,
      'advanced': framesDrawn,
    },
    'coverage': <String, dynamic>{
      'framesDrawn': framesDrawn,
      'framesSummarized': framesSummarized,
      'complete': complete,
      if (!complete) 'detail': 'describes a subset of this session',
    },
    'frameSummary': <String, dynamic>{
      'frame_count': framesSummarized,
      'worst_frame_build_time_millis': 114.0,
    },
    'blockAttribution': <Map<String, Object?>>[],
  };
}

void main() {
  group('DuskPerfEndCommand', () {
    test('name is dusk:perf_end', () {
      expect(DuskPerfEndCommand().name, equals('dusk:perf_end'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskPerfEndCommand().boot, equals(CommandBoot.connected));
    });

    test('the human line warns when the summary covers a subset of frames',
        () async {
      // This is the line that misled a real investigation: "2 frames, worst
      // build 114ms" printed over a session that drew 4, with an empty
      // attribution, and read as a complete measurement. The JSON knew; the
      // sentence a human reads did not say it.
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: _report(framesDrawn: 4, framesSummarized: 2),
      );

      final code = await DuskPerfEndCommand().handle(ctx);

      expect(code, equals(0), reason: 'a partial report is still a report');
      expect(output.content, contains('4'));
      expect(output.content, contains('2'));
      expect(output.content.toLowerCase(), contains('subset'));
    });

    test('a complete session prints no coverage warning', () async {
      // A warning that fires on every run is one a reader stops seeing.
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: _report(framesDrawn: 9, framesSummarized: 9),
      );

      await DuskPerfEndCommand().handle(ctx);

      expect(output.content, contains('9 frames'));
      expect(output.content.toLowerCase(), isNot(contains('subset')));
    });

    test('a refusal still exits non-zero', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const <String, dynamic>{
          'refused': true,
          'reason': 'nothing was driven',
        },
      );

      expect(await DuskPerfEndCommand().handle(ctx), equals(1));
    });
  });
}
