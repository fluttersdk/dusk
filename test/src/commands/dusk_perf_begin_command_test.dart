import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_begin_command.dart';

class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
    required Map<String, dynamic> response,
  })  : _response = response,
        super.bare(input, output);

  final Map<String, dynamic> _response;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('DuskPerfBeginCommand', () {
    test('name is dusk:perf_begin', () {
      expect(DuskPerfBeginCommand().name, equals('dusk:perf_begin'));
    });

    test('--mode accepts only attribution and timing', () {
      final ArgParser parser = ArgParser();
      DuskPerfBeginCommand().configure(parser);

      expect(parser.options['mode']!.allowed, <String>[
        'attribution',
        'timing',
      ]);
      expect(parser.options['mode']!.defaultsTo, 'attribution');
    });

    test('forwards the mode and names it in the human line', () async {
      final BufferedOutput output = BufferedOutput();
      final _StubContext ctx = _StubContext(
        input: MapInput(const <String, dynamic>{'mode': 'timing'}),
        output: output,
        response: const <String, dynamic>{
          'sessionToken': 'perf-3',
          'mode': 'timing',
        },
      );

      final int code = await DuskPerfBeginCommand().handle(ctx);

      expect(code, 0);
      expect(ctx.lastParams, containsPair('mode', 'timing'));
      expect(ctx.lastParams, containsPair('phases', 'false'));
      expect(output.content, contains('perf-3'));
      expect(output.content, contains('timing'));
    });
  });
}
