import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_fill_command.dart';

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
  group('DuskFillCommand', () {
    test('name is dusk:fill', () {
      expect(DuskFillCommand().name, equals('dusk:fill'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskFillCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref and --text options', () {
      final parser = ArgParser();
      DuskFillCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['ref', 'text']));
    });

    test('handle forwards --ref and --text to ext.dusk.fill', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'text': 'hello'}),
        output: BufferedOutput(),
      );
      final exit = await DuskFillCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.fill'));
      expect(ctx.lastParams, containsPair('ref', 'e5'));
      expect(ctx.lastParams, containsPair('text', 'hello'));
    });

    test('handle returns 1 when --ref is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'hello'}),
        output: BufferedOutput(),
      );
      final exit = await DuskFillCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });
  });
}
