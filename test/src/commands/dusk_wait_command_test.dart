import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_wait_command.dart';

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
  group('DuskWaitCommand', () {
    test('name is dusk:wait', () {
      expect(DuskWaitCommand().name, equals('dusk:wait'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskWaitCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskWaitCommand().description, isNotEmpty);
    });

    test('configure declares --text / --textGone / --expression / --timeoutMs',
        () {
      // Switched from the signature-DSL to configure(ArgParser) so the
      // camelCase option names (textGone / timeoutMs) pass artisan's
      // signature-parser strict-lowercase rule. Inspect the configured
      // parser directly.
      final parser = ArgParser();
      DuskWaitCommand().configure(parser);
      expect(
          parser.options.keys,
          containsAll(<String>[
            'text',
            'textGone',
            'expression',
            'timeoutMs',
          ]));
    });

    test('handle calls ext.dusk.wait_for', () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'Loading...'}),
        output: BufferedOutput(),
        response: const {'matched': true},
      );

      await DuskWaitCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.wait_for'));
    });

    test('handle forwards --text param when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'Done'}),
        output: BufferedOutput(),
        response: const {'matched': true},
      );

      await DuskWaitCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('text', 'Done'));
    });

    test('handle forwards --textGone param when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'textGone': 'Loading'}),
        output: BufferedOutput(),
        response: const {'matched': true},
      );

      await DuskWaitCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('textGone', 'Loading'));
    });

    test('handle forwards --expression param when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'expression': 'controller.isReady'}),
        output: BufferedOutput(),
        response: const {'matched': true},
      );

      await DuskWaitCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('expression', 'controller.isReady'));
    });

    test(
        'handle forwards --timeoutMs param when provided alongside a condition',
        () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'Ready', 'timeoutMs': '5000'}),
        output: BufferedOutput(),
        response: const {'matched': true},
      );

      await DuskWaitCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('timeoutMs', '5000'));
    });

    test('handle returns 1 when no condition option is provided', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
      );

      final code = await DuskWaitCommand().handle(ctx);

      expect(code, equals(1));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'Ready'}),
        output: BufferedOutput(),
        response: const {'matched': true},
      );

      expect(await DuskWaitCommand().handle(ctx), equals(0));
    });
  });
}
