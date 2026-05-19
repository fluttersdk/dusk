import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_tap_command.dart';

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
  group('DuskTapCommand', () {
    test('name is dusk:tap', () {
      expect(DuskTapCommand().name, equals('dusk:tap'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskTapCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref option', () {
      final parser = ArgParser();
      DuskTapCommand().configure(parser);
      expect(parser.options.keys, contains('ref'));
    });

    test('handle forwards --ref to ext.dusk.tap', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );
      final exit = await DuskTapCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.tap'));
      expect(ctx.lastParams, equals({'ref': 'e5'}));
    });

    test('handle accepts q-shape refs (Playwright Locator path)', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'q3'}),
        output: BufferedOutput(),
      );
      await DuskTapCommand().handle(ctx);
      expect(ctx.lastParams, equals({'ref': 'q3'}));
    });

    test('handle returns 1 when --ref is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await DuskTapCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns 1 when --ref is empty', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': ''}),
        output: BufferedOutput(),
      );
      final exit = await DuskTapCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });
  });
}
