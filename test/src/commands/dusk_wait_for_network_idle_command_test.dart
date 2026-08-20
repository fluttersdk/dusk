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

    test('returns 1 and says so when the network never went idle', () async {
      // The handler answers a timeout with a SUCCESS envelope carrying
      // `matched: false`, the same shape ext.dusk.wait_for uses. This is
      // the command a CI script is most likely to chain on, so passing
      // there proves nothing and stops nothing.
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'matched': false, 'reason': 'timeout'},
      );

      final int exit = await DuskWaitForNetworkIdleCommand().handle(ctx);

      expect(exit, equals(1));
      expect(output.content, contains('did not go idle'));
      expect(output.content, isNot(contains('Network idle')));
    });

    test('returns 0 when the network did go idle', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'matched': true, 'elapsedMs': 120},
      );

      final int exit = await DuskWaitForNetworkIdleCommand().handle(ctx);

      expect(exit, equals(0));
      expect(output.content, contains('Network idle'));
    });
  });
}
