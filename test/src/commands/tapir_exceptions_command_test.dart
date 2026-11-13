import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_exceptions_command.dart';

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
  group('TapirExceptionsCommand', () {
    test('name is tapir:exceptions', () {
      expect(TapirExceptionsCommand().name, equals('tapir:exceptions'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirExceptionsCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirExceptionsCommand().description, isNotEmpty);
    });

    test('configure declares --limit option', () {
      final parser = ArgParser();
      TapirExceptionsCommand().configure(parser);
      expect(parser.options.keys, contains('limit'));
    });

    test('handle calls ext.tapir.exceptions', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      await TapirExceptionsCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.exceptions'));
    });

    test('handle forwards --limit param', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '5'}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      await TapirExceptionsCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '5'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      expect(await TapirExceptionsCommand().handle(ctx), equals(0));
    });
    test('handle forwards --clear so a sweep reads a delta', () async {
      final ctx = _StubContext(
        input: MapInput(const {'clear': true}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      await TapirExceptionsCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('clear', 'true'));
    });

    test('handle omits clear when the caller did not ask for it', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      await TapirExceptionsCommand().handle(ctx);

      expect(ctx.lastParams!.containsKey('clear'), isFalse);
    });
  });
}
