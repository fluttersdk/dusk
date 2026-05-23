import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_scroll_command.dart';

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
  group('DuskScrollCommand', () {
    test('name is dusk:scroll', () {
      expect(DuskScrollCommand().name, equals('dusk:scroll'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskScrollCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskScrollCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.scroll with ref', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.scroll'));
      expect(ctx.lastParams, containsPair('ref', 'e5'));
    });

    test('handle forwards dy when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'dy': '-300'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dy', '-300'));
    });

    test('handle forwards dx when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'dx': '100'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dx', '100'));
    });

    test('handle forwards intoView flag when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'intoView': true}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('intoView', 'true'));
    });

    test('handle returns 1 and prints error when ref is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
      );

      final code = await DuskScrollCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('ref'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );

      expect(await DuskScrollCommand().handle(ctx), equals(0));
    });

    test('handle translates --direction=down --pixels=200 to positive --dy',
        () async {
      final ctx = _StubContext(
        input:
            MapInput(const {'ref': 'e5', 'direction': 'down', 'pixels': '200'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.scroll'));
      expect(ctx.lastParams, containsPair('dy', '200.0'));
    });

    test('handle translates --direction=up --pixels=300 to negative --dy',
        () async {
      final ctx = _StubContext(
        input:
            MapInput(const {'ref': 'e5', 'direction': 'up', 'pixels': '300'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dy', '-300.0'));
    });

    test('handle translates --direction=right --pixels=150 to positive --dx',
        () async {
      final ctx = _StubContext(
        input: MapInput(
            const {'ref': 'e5', 'direction': 'right', 'pixels': '150'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dx', '150.0'));
    });

    test('handle translates --direction=left --pixels=80 to negative --dx',
        () async {
      final ctx = _StubContext(
        input:
            MapInput(const {'ref': 'e5', 'direction': 'left', 'pixels': '80'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dx', '-80.0'));
    });

    test('handle prefers explicit --dy/--dx over --direction/--pixels',
        () async {
      final ctx = _StubContext(
        input: MapInput(const {
          'ref': 'e5',
          'dy': '500',
          'direction': 'up',
          'pixels': '50',
        }),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      // Explicit --dy=500 wins over --direction=up (which would have produced --dy=-50).
      expect(ctx.lastParams, containsPair('dy', '500'));
      expect(ctx.lastParams, isNot(containsPair('dy', '-50.0')));
    });
  });
}
