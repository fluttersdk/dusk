import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_perf_insight_command.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    this._response = const <String, dynamic>{},
  }) : super.bare(input, output);

  final Map<String, dynamic> _response;
  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('TapirPerfInsightCommand', () {
    test('name is tapir:perf_insight and boot is connected', () {
      expect(TapirPerfInsightCommand().name, equals('tapir:perf_insight'));
      expect(TapirPerfInsightCommand().boot, equals(CommandBoot.connected));
    });

    test('a missing --id exits 1 without calling the extension', () async {
      final _StubContext ctx = _StubContext(
        input: MapInput(const <String, dynamic>{}),
        output: BufferedOutput(),
      );

      expect(await TapirPerfInsightCommand().handle(ctx), 1);
      expect(ctx.lastMethod, isNull);
    });

    test(
      'forwards --id and --token and prints title, summary, next step',
      () async {
        final BufferedOutput output = BufferedOutput();
        final _StubContext ctx = _StubContext(
          input: MapInput(const <String, dynamic>{
            'id': 'I2',
            'token': 'perf-4',
          }),
          output: output,
          response: const <String, dynamic>{
            'sessionToken': 'perf-4',
            'id': 'I2',
            'severity': 'warn',
            'title': 'One block owns the self time',
            'summary': 'MonitorRow spent 40% of self time.',
            'detail': <String, dynamic>{},
            'estimatedSavingsMs': 12.5,
            'nextStep': 'Look at MonitorRow.build.',
          },
        );

        final int code = await TapirPerfInsightCommand().handle(ctx);

        expect(code, 0);
        expect(ctx.lastMethod, 'ext.tapir.perf_insight');
        expect(ctx.lastParams, <String, dynamic>{
          'id': 'I2',
          'token': 'perf-4',
        });
        expect(output.content, contains('One block owns the self time'));
        expect(output.content, contains('MonitorRow spent 40%'));
        expect(output.content, contains('Look at MonitorRow.build.'));
        expect(output.content, contains('12.5'));
      },
    );

    test('omits the token when the caller did not pass one', () async {
      final _StubContext ctx = _StubContext(
        input: MapInput(const <String, dynamic>{'id': 'I1'}),
        output: BufferedOutput(),
        response: const <String, dynamic>{'id': 'I1', 'title': 't'},
      );

      await TapirPerfInsightCommand().handle(ctx);

      expect(ctx.lastParams, <String, dynamic>{'id': 'I1'});
    });
  });
}
