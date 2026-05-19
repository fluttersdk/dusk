import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_type_command.dart';

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
  group('DuskTypeCommand', () {
    test('name is dusk:type', () {
      expect(DuskTypeCommand().name, equals('dusk:type'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskTypeCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskTypeCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.type with ref and text', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3', 'text': 'hello'}),
        output: BufferedOutput(),
      );

      await DuskTypeCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.type'));
      expect(ctx.lastParams, containsPair('ref', 'e3'));
      expect(ctx.lastParams, containsPair('text', 'hello'));
    });

    test('handle returns 1 and prints error when ref is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'text': 'hello'}),
        output: output,
      );

      final code = await DuskTypeCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('ref'));
    });

    test('handle returns 1 and prints error when text is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3'}),
        output: output,
      );

      final code = await DuskTypeCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('text'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3', 'text': 'hello'}),
        output: BufferedOutput(),
      );

      expect(await DuskTypeCommand().handle(ctx), equals(0));
    });
  });
}
