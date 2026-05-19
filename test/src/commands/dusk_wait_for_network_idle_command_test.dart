import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_wait_for_network_idle_command.dart';

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
  group('DuskWaitForNetworkIdleCommand', () {
    test('name is dusk:wait_for_network_idle', () {
      expect(
        DuskWaitForNetworkIdleCommand().name,
        equals('dusk:wait_for_network_idle'),
      );
    });

    test('boot is CommandBoot.connected', () {
      expect(
        DuskWaitForNetworkIdleCommand().boot,
        equals(CommandBoot.connected),
      );
    });

    test('description is non-empty', () {
      expect(DuskWaitForNetworkIdleCommand().description, isNotEmpty);
    });

    test('configure declares --timeoutMs / --idleMs / --pollIntervalMs', () {
      final parser = ArgParser();
      DuskWaitForNetworkIdleCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>[
          'timeoutMs',
          'idleMs',
          'pollIntervalMs',
        ]),
      );
    });

    test('handle calls ext.dusk.wait_for_network_idle', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'matched': true, 'idleAchievedMs': 500},
      );

      await DuskWaitForNetworkIdleCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.wait_for_network_idle'));
    });

    test('handle forwards --timeoutMs / --idleMs / --pollIntervalMs params',
        () async {
      final ctx = _StubContext(
        input: MapInput(const {
          'timeoutMs': '8000',
          'idleMs': '750',
          'pollIntervalMs': '150',
        }),
        output: BufferedOutput(),
        response: const {'matched': true, 'idleAchievedMs': 750},
      );

      await DuskWaitForNetworkIdleCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('timeoutMs', '8000'));
      expect(ctx.lastParams, containsPair('idleMs', '750'));
      expect(ctx.lastParams, containsPair('pollIntervalMs', '150'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'matched': true, 'idleAchievedMs': 500},
      );

      expect(await DuskWaitForNetworkIdleCommand().handle(ctx), equals(0));
    });
  });
}
