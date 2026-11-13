import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_console_command.dart';

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
  group('TapirConsoleCommand', () {
    test('name is tapir:console', () {
      expect(TapirConsoleCommand().name, equals('tapir:console'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirConsoleCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirConsoleCommand().description, isNotEmpty);
    });

    test('configure declares --limit and --minLevel', () {
      final parser = ArgParser();
      TapirConsoleCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['limit', 'minLevel']));
    });

    test('handle calls ext.tapir.console', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'logs': <dynamic>[], 'count': 0},
      );

      await TapirConsoleCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.console'));
    });

    test('handle forwards --limit and --minLevel params', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '10', 'minLevel': 'WARNING'}),
        output: BufferedOutput(),
        response: const {'logs': <dynamic>[], 'count': 0},
      );

      await TapirConsoleCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '10'));
      expect(ctx.lastParams, containsPair('minLevel', 'WARNING'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'logs': <dynamic>[], 'count': 0},
      );

      expect(await TapirConsoleCommand().handle(ctx), equals(0));
    });
  });
}
