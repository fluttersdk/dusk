import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_drag_command.dart';

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
  group('TapirDragCommand', () {
    test('name is tapir:drag', () {
      expect(TapirDragCommand().name, equals('tapir:drag'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirDragCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirDragCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.drag with startRef and endRef', () async {
      final ctx = _StubContext(
        input: MapInput(const {'startRef': 'e2', 'endRef': 'e9'}),
        output: BufferedOutput(),
      );

      await TapirDragCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.drag'));
      expect(ctx.lastParams, containsPair('startRef', 'e2'));
      expect(ctx.lastParams, containsPair('endRef', 'e9'));
    });

    test(
      'handle returns 1 and prints error when startRef is missing',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'endRef': 'e9'}),
          output: output,
        );

        final code = await TapirDragCommand().handle(ctx);

        expect(code, equals(1));
        expect(output.content, contains('startRef'));
      },
    );

    test('handle returns 1 and prints error when endRef is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'startRef': 'e2'}),
        output: output,
      );

      final code = await TapirDragCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('endRef'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'startRef': 'e2', 'endRef': 'e9'}),
        output: BufferedOutput(),
      );

      expect(await TapirDragCommand().handle(ctx), equals(0));
    });

    test('handle accepts --fromRef/--toRef aliases', () async {
      final ctx = _StubContext(
        input: MapInput(const {'fromRef': 'e4', 'toRef': 'e7'}),
        output: BufferedOutput(),
      );

      final code = await TapirDragCommand().handle(ctx);

      expect(code, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.drag'));
      expect(ctx.lastParams, containsPair('startRef', 'e4'));
      expect(ctx.lastParams, containsPair('endRef', 'e7'));
    });

    test(
      'handle prefers --fromRef over legacy --startRef when both supplied',
      () async {
        final ctx = _StubContext(
          input: MapInput(const {
            'fromRef': 'e9',
            'startRef': 'e2',
            'toRef': 'e10',
          }),
          output: BufferedOutput(),
        );

        await TapirDragCommand().handle(ctx);

        expect(ctx.lastParams, containsPair('startRef', 'e9'));
        expect(ctx.lastParams, containsPair('endRef', 'e10'));
      },
    );
  });
}
