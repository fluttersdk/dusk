import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_select_option_command.dart';

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
  group('TapirSelectOptionCommand', () {
    test('name is tapir:select_option', () {
      expect(TapirSelectOptionCommand().name, equals('tapir:select_option'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirSelectOptionCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref and --value', () {
      final parser = ArgParser();
      TapirSelectOptionCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['ref', 'value']));
    });

    test(
      'handle forwards --ref + --value to ext.tapir.select_option',
      () async {
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e4', 'value': 'Japonya'}),
          output: BufferedOutput(),
        );
        await TapirSelectOptionCommand().handle(ctx);
        expect(ctx.lastMethod, equals('ext.tapir.select_option'));
        expect(
          ctx.lastParams,
          allOf(containsPair('ref', 'e4'), containsPair('value', 'Japonya')),
        );
      },
    );

    test('handle returns 1 when --ref is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {'value': 'Japonya'}),
        output: BufferedOutput(),
      );
      final exit = await TapirSelectOptionCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns 1 when --value is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e4'}),
        output: BufferedOutput(),
      );
      final exit = await TapirSelectOptionCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });
  });
}
