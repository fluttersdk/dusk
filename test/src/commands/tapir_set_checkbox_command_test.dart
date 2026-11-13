import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_set_checkbox_command.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
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
  group('TapirSetCheckboxCommand', () {
    test('name is tapir:set_checkbox', () {
      expect(TapirSetCheckboxCommand().name, equals('tapir:set_checkbox'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirSetCheckboxCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirSetCheckboxCommand().description, isNotEmpty);
    });

    test('configure declares --ref and --value options', () {
      final parser = ArgParser();
      TapirSetCheckboxCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>['ref', 'value']),
      );
    });

    test('handle calls ext.tapir.set_checkbox', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'true'}),
        output: BufferedOutput(),
        response: const {
          'ref': 'e5',
          'previousValue': false,
          'value': true,
          'toggled': true,
        },
      );

      await TapirSetCheckboxCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.set_checkbox'));
    });

    test('handle forwards --ref and --value params', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'true'}),
        output: BufferedOutput(),
        response: const {
          'ref': 'e5',
          'previousValue': false,
          'value': true,
          'toggled': true,
        },
      );

      await TapirSetCheckboxCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('ref', 'e5'));
      expect(ctx.lastParams, containsPair('value', 'true'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'false'}),
        output: BufferedOutput(),
        response: const {
          'ref': 'e5',
          'previousValue': true,
          'value': false,
          'toggled': true,
        },
      );

      expect(await TapirSetCheckboxCommand().handle(ctx), equals(0));
    });
  });
}
