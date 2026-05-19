import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_hover_command.dart';

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
  group('DuskHoverCommand', () {
    test('name is dusk:hover', () {
      expect(DuskHoverCommand().name, equals('dusk:hover'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskHoverCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskHoverCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.hover with ref', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
      );

      await DuskHoverCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.hover'));
      expect(ctx.lastParams, containsPair('ref', 'e7'));
    });

    test('handle returns 1 and prints error when ref is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
      );

      final code = await DuskHoverCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('ref'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
      );

      expect(await DuskHoverCommand().handle(ctx), equals(0));
    });
  });
}
