import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_perf_begin_command.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    required this._response,
  }) : super.bare(input, output);

  final Map<String, dynamic> _response;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('TapirPerfBeginCommand', () {
    test('name is tapir:perf_begin', () {
      expect(TapirPerfBeginCommand().name, equals('tapir:perf_begin'));
    });

    test('--mode accepts only attribution and timing', () {
      final ArgParser parser = ArgParser();
      TapirPerfBeginCommand().configure(parser);

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

      final int code = await TapirPerfBeginCommand().handle(ctx);

      expect(code, 0);
      expect(ctx.lastParams, containsPair('mode', 'timing'));
      expect(ctx.lastParams, containsPair('phases', 'false'));
      expect(output.content, contains('perf-3'));
      expect(output.content, contains('timing'));
    });
  });
}
