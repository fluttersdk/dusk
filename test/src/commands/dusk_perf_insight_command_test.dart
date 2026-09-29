import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_insight_command.dart';

class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
    Map<String, dynamic> response = const <String, dynamic>{},
  })  : _response = response,
        super.bare(input, output);

  final Map<String, dynamic> _response;
  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('DuskPerfInsightCommand', () {
    test('name is dusk:perf_insight and boot is connected', () {
      expect(DuskPerfInsightCommand().name, equals('dusk:perf_insight'));
      expect(DuskPerfInsightCommand().boot, equals(CommandBoot.connected));
    });

    test('a missing --id exits 1 without calling the extension', () async {
      final _StubContext ctx = _StubContext(
        input: MapInput(const <String, dynamic>{}),
        output: BufferedOutput(),
      );

      expect(await DuskPerfInsightCommand().handle(ctx), 1);
      expect(ctx.lastMethod, isNull);
    });

    test('forwards --id and --token and prints title, summary, next step',
        () async {
      final BufferedOutput output = BufferedOutput();
      final _StubContext ctx = _StubContext(
        input: MapInput(const <String, dynamic>{'id': 'I2', 'token': 'perf-4'}),
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

      final int code = await DuskPerfInsightCommand().handle(ctx);

      expect(code, 0);
      expect(ctx.lastMethod, 'ext.dusk.perf_insight');
      expect(ctx.lastParams, <String, dynamic>{'id': 'I2', 'token': 'perf-4'});
      expect(output.content, contains('One block owns the self time'));
      expect(output.content, contains('MonitorRow spent 40%'));
      expect(output.content, contains('Look at MonitorRow.build.'));
      expect(output.content, contains('12.5'));
    });

    test('omits the token when the caller did not pass one', () async {
      final _StubContext ctx = _StubContext(
        input: MapInput(const <String, dynamic>{'id': 'I1'}),
        output: BufferedOutput(),
        response: const <String, dynamic>{'id': 'I1', 'title': 't'},
      );

      await DuskPerfInsightCommand().handle(ctx);

      expect(ctx.lastParams, <String, dynamic>{'id': 'I1'});
    });
  });
}
