import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_modal_command.dart';

/// Stubs [ArtisanContext.callExtension] so tests never hit a real VM Service.
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
  group('DuskModalCommand', () {
    test('name is dusk:modal', () {
      expect(DuskModalCommand().name, equals('dusk:modal'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskModalCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskModalCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.dismiss_modals', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'dismissed': 1},
      );

      await DuskModalCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.dismiss_modals'));
    });

    test('handle passes no params to dismiss_modals', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'dismissed': 1},
      );

      await DuskModalCommand().handle(ctx);

      expect(ctx.lastParams, isNull);
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'dismissed': 0},
      );

      expect(await DuskModalCommand().handle(ctx), equals(0));
    });
  });
}
