import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_dblclick_command.dart';

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
  group('TapirDblclickCommand', () {
    test('name is tapir:dblclick', () {
      expect(TapirDblclickCommand().name, equals('tapir:dblclick'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirDblclickCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirDblclickCommand().description, isNotEmpty);
    });

    test('configure declares --ref option', () {
      final parser = ArgParser();
      TapirDblclickCommand().configure(parser);
      expect(parser.options.keys, contains('ref'));
    });

    test('handle calls ext.tapir.dblclick', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3'}),
        output: BufferedOutput(),
        response: const {'ref': 'e3'},
      );

      await TapirDblclickCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.dblclick'));
    });

    test('handle forwards --ref param', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
        response: const {'ref': 'e7'},
      );

      await TapirDblclickCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('ref', 'e7'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3'}),
        output: BufferedOutput(),
        response: const {'ref': 'e3'},
      );

      expect(await TapirDblclickCommand().handle(ctx), equals(0));
    });
  });
}
