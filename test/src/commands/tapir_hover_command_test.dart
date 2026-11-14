import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_hover_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
class _StubContext extends DowelContext {
  _StubContext({required DowelInput input, required DowelOutput output})
    : _response = const {},
      super.bare(input, output);

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
  group('TapirHoverCommand', () {
    test('name is tapir:hover', () {
      expect(TapirHoverCommand().name, equals('tapir:hover'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirHoverCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirHoverCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.hover with ref', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
      );

      await TapirHoverCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.hover'));
      expect(ctx.lastParams, containsPair('ref', 'e7'));
    });

    test('handle returns 1 and prints error when ref is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(input: MapInput(const {}), output: output);

      final code = await TapirHoverCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('ref'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
      );

      expect(await TapirHoverCommand().handle(ctx), equals(0));
    });
  });
}
