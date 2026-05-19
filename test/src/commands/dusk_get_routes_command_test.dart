import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_get_routes_command.dart';

class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
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
  group('DuskGetRoutesCommand', () {
    test('name is dusk:get_routes', () {
      expect(DuskGetRoutesCommand().name, equals('dusk:get_routes'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskGetRoutesCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskGetRoutesCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.get_routes + prints JSON to output', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'location': '/forms', 'title': 'Forms'},
      );
      final exit = await DuskGetRoutesCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.get_routes'));
      // The handler pretty-prints the response as JSON; assert both fields
      // appear in the output buffer.
      final printed = output.content;
      expect(printed, contains('"location": "/forms"'));
      expect(printed, contains('"title": "Forms"'));
    });
  });
}
