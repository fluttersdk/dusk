import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_select_option_command.dart';

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
  group('DuskSelectOptionCommand', () {
    test('name is dusk:select_option', () {
      expect(DuskSelectOptionCommand().name, equals('dusk:select_option'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskSelectOptionCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref and --value', () {
      final parser = ArgParser();
      DuskSelectOptionCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['ref', 'value']));
    });

    test('handle forwards --ref + --value to ext.dusk.select_option', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e4', 'value': 'Japonya'}),
        output: BufferedOutput(),
      );
      await DuskSelectOptionCommand().handle(ctx);
      expect(ctx.lastMethod, equals('ext.dusk.select_option'));
      expect(
        ctx.lastParams,
        allOf(containsPair('ref', 'e4'), containsPair('value', 'Japonya')),
      );
    });

    test('handle returns 1 when --ref is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {'value': 'Japonya'}),
        output: BufferedOutput(),
      );
      final exit = await DuskSelectOptionCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns 1 when --value is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e4'}),
        output: BufferedOutput(),
      );
      final exit = await DuskSelectOptionCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });
  });
}
