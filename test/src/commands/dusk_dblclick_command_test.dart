import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_dblclick_command.dart';

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
  group('DuskDblclickCommand', () {
    test('name is dusk:dblclick', () {
      expect(DuskDblclickCommand().name, equals('dusk:dblclick'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskDblclickCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskDblclickCommand().description, isNotEmpty);
    });

    test('configure declares --ref option', () {
      final parser = ArgParser();
      DuskDblclickCommand().configure(parser);
      expect(parser.options.keys, contains('ref'));
    });

    test('handle calls ext.dusk.dblclick', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3'}),
        output: BufferedOutput(),
        response: const {'ref': 'e3'},
      );

      await DuskDblclickCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.dblclick'));
    });

    test('handle forwards --ref param', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
        response: const {'ref': 'e7'},
      );

      await DuskDblclickCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('ref', 'e7'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3'}),
        output: BufferedOutput(),
        response: const {'ref': 'e3'},
      );

      expect(await DuskDblclickCommand().handle(ctx), equals(0));
    });
  });
}
