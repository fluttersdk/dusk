import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_modal_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    this._response = const {},
  }) : super.bare(input, output);

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
  group('TapirModalCommand', () {
    test('name is tapir:modal', () {
      expect(TapirModalCommand().name, equals('tapir:modal'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirModalCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirModalCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.dismiss_modals', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'dismissed': 1},
      );

      await TapirModalCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.dismiss_modals'));
    });

    test('handle passes no params to dismiss_modals', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'dismissed': 1},
      );

      await TapirModalCommand().handle(ctx);

      expect(ctx.lastParams, isNull);
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'dismissed': 0},
      );

      expect(await TapirModalCommand().handle(ctx), equals(0));
    });
  });
}
