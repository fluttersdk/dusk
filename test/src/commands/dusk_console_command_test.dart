import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_console_command.dart';

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
  group('DuskConsoleCommand', () {
    test('name is dusk:console', () {
      expect(DuskConsoleCommand().name, equals('dusk:console'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskConsoleCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskConsoleCommand().description, isNotEmpty);
    });

    test('configure declares --limit and --minLevel', () {
      final parser = ArgParser();
      DuskConsoleCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>['limit', 'minLevel']),
      );
    });

    test('handle calls ext.dusk.console', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'logs': <dynamic>[], 'count': 0},
      );

      await DuskConsoleCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.console'));
    });

    test('handle forwards --limit and --minLevel params', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '10', 'minLevel': 'WARNING'}),
        output: BufferedOutput(),
        response: const {'logs': <dynamic>[], 'count': 0},
      );

      await DuskConsoleCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '10'));
      expect(ctx.lastParams, containsPair('minLevel', 'WARNING'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'logs': <dynamic>[], 'count': 0},
      );

      expect(await DuskConsoleCommand().handle(ctx), equals(0));
    });
  });
}
