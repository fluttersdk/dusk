import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_observe_command.dart';

/// Stubs [ArtisanContext.callExtension] so tests never hit a real VM Service.
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
  group('DuskObserveCommand', () {
    test('name is dusk:observe', () {
      expect(DuskObserveCommand().name, equals('dusk:observe'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskObserveCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskObserveCommand().description, isNotEmpty);
    });

    test('configure declares --intent / --roles / --limit / --includeEnrichers',
        () {
      final parser = ArgParser();
      DuskObserveCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>[
          'intent',
          'roles',
          'limit',
          'includeEnrichers',
        ]),
      );
    });

    test('handle calls ext.dusk.observe', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'candidates': <dynamic>[], 'count': 0},
      );

      await DuskObserveCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.observe'));
    });

    test('handle forwards every option as a string param', () async {
      final ctx = _StubContext(
        input: MapInput(const {
          'intent': 'login form',
          'roles': 'button,textbox',
          'limit': '20',
          'includeEnrichers': 'full',
        }),
        output: BufferedOutput(),
        response: const {'candidates': <dynamic>[], 'count': 0},
      );

      await DuskObserveCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('intent', 'login form'));
      expect(ctx.lastParams, containsPair('roles', 'button,textbox'));
      expect(ctx.lastParams, containsPair('limit', '20'));
      expect(ctx.lastParams, containsPair('includeEnrichers', 'full'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'candidates': <dynamic>[], 'count': 0},
      );

      expect(await DuskObserveCommand().handle(ctx), equals(0));
    });
  });
}
