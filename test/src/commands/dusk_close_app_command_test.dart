import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_close_app_command.dart';

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
  group('DuskCloseAppCommand', () {
    test('name is dusk:close_app', () {
      expect(DuskCloseAppCommand().name, equals('dusk:close_app'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskCloseAppCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskCloseAppCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.close_app with no params', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await DuskCloseAppCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.close_app'));
      expect(ctx.lastParams, isEmpty);
    });
  });
}
