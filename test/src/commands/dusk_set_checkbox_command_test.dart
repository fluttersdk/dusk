import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_set_checkbox_command.dart';

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
  group('DuskSetCheckboxCommand', () {
    test('name is dusk:set_checkbox', () {
      expect(DuskSetCheckboxCommand().name, equals('dusk:set_checkbox'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskSetCheckboxCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskSetCheckboxCommand().description, isNotEmpty);
    });

    test('configure declares --ref and --value options', () {
      final parser = ArgParser();
      DuskSetCheckboxCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>['ref', 'value']),
      );
    });

    test('handle calls ext.dusk.set_checkbox', () async {
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

      await DuskSetCheckboxCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.set_checkbox'));
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

      await DuskSetCheckboxCommand().handle(ctx);

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

      expect(await DuskSetCheckboxCommand().handle(ctx), equals(0));
    });
  });
}
