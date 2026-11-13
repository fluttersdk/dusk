import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_observe_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
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
  group('TapirObserveCommand', () {
    test('name is tapir:observe', () {
      expect(TapirObserveCommand().name, equals('tapir:observe'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirObserveCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirObserveCommand().description, isNotEmpty);
    });

    test('configure declares --intent / --roles / --limit / --includeEnrichers',
        () {
      final parser = ArgParser();
      TapirObserveCommand().configure(parser);
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

    test('handle calls ext.tapir.observe', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'candidates': <dynamic>[], 'count': 0},
      );

      await TapirObserveCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.observe'));
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

      await TapirObserveCommand().handle(ctx);

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

      expect(await TapirObserveCommand().handle(ctx), equals(0));
    });
  });
}
