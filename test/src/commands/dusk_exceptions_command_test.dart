import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_exceptions_command.dart';

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
  group('DuskExceptionsCommand', () {
    test('name is dusk:exceptions', () {
      expect(DuskExceptionsCommand().name, equals('dusk:exceptions'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskExceptionsCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskExceptionsCommand().description, isNotEmpty);
    });

    test('configure declares --limit option', () {
      final parser = ArgParser();
      DuskExceptionsCommand().configure(parser);
      expect(parser.options.keys, contains('limit'));
    });

    test('handle calls ext.dusk.exceptions', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      await DuskExceptionsCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.exceptions'));
    });

    test('handle forwards --limit param', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '5'}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      await DuskExceptionsCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '5'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[], 'count': 0},
      );

      expect(await DuskExceptionsCommand().handle(ctx), equals(0));
    });
  });
}
