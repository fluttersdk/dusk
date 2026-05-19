import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_drag_command.dart';

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
  group('DuskDragCommand', () {
    test('name is dusk:drag', () {
      expect(DuskDragCommand().name, equals('dusk:drag'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskDragCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskDragCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.drag with startRef and endRef', () async {
      final ctx = _StubContext(
        input: MapInput(const {'startRef': 'e2', 'endRef': 'e9'}),
        output: BufferedOutput(),
      );

      await DuskDragCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.drag'));
      expect(ctx.lastParams, containsPair('startRef', 'e2'));
      expect(ctx.lastParams, containsPair('endRef', 'e9'));
    });

    test('handle returns 1 and prints error when startRef is missing',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'endRef': 'e9'}),
        output: output,
      );

      final code = await DuskDragCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('startRef'));
    });

    test('handle returns 1 and prints error when endRef is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'startRef': 'e2'}),
        output: output,
      );

      final code = await DuskDragCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('endRef'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'startRef': 'e2', 'endRef': 'e9'}),
        output: BufferedOutput(),
      );

      expect(await DuskDragCommand().handle(ctx), equals(0));
    });
  });
}
