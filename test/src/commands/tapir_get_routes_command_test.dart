import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_get_routes_command.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    Map<String, dynamic> response = const {},
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
  group('TapirGetRoutesCommand', () {
    test('name is tapir:get_routes', () {
      expect(TapirGetRoutesCommand().name, equals('tapir:get_routes'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirGetRoutesCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirGetRoutesCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.get_routes + prints JSON to output', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'location': '/forms', 'title': 'Forms'},
      );
      final exit = await TapirGetRoutesCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.get_routes'));
      // The handler pretty-prints the response as JSON; assert both fields
      // appear in the output buffer.
      final printed = output.content;
      expect(printed, contains('"location": "/forms"'));
      expect(printed, contains('"title": "Forms"'));
    });
  });
}
