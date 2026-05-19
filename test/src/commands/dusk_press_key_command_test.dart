import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_press_key_command.dart';

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
  group('DuskPressKeyCommand', () {
    test('name is dusk:press_key', () {
      expect(DuskPressKeyCommand().name, equals('dusk:press_key'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskPressKeyCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --key and --modifiers', () {
      final parser = ArgParser();
      DuskPressKeyCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['key', 'modifiers']));
    });

    test('handle forwards --key only when modifiers omitted', () async {
      final ctx = _StubContext(
        input: MapInput(const {'key': 'Enter'}),
        output: BufferedOutput(),
      );
      await DuskPressKeyCommand().handle(ctx);
      expect(ctx.lastMethod, equals('ext.dusk.press_key'));
      expect(ctx.lastParams, equals({'key': 'Enter'}));
    });

    test('handle forwards --key + --modifiers when both present', () async {
      final ctx = _StubContext(
        input: MapInput(const {'key': 'a', 'modifiers': 'ctrl,shift'}),
        output: BufferedOutput(),
      );
      await DuskPressKeyCommand().handle(ctx);
      expect(ctx.lastParams, equals({'key': 'a', 'modifiers': 'ctrl,shift'}));
    });

    test('handle returns 1 when --key is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await DuskPressKeyCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });
  });
}
