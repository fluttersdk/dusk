import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_tap_command.dart';

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
  group('DuskTapCommand', () {
    test('name is dusk:tap', () {
      expect(DuskTapCommand().name, equals('dusk:tap'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskTapCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref option', () {
      final parser = ArgParser();
      DuskTapCommand().configure(parser);
      expect(parser.options.keys, contains('ref'));
    });

    test('handle forwards --ref to ext.dusk.tap', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );
      final exit = await DuskTapCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.tap'));
      expect(ctx.lastParams, containsPair('ref', 'e5'));
    });

    test('handle accepts q-shape refs (Playwright Locator path)', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'q3'}),
        output: BufferedOutput(),
      );
      await DuskTapCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('ref', 'q3'));
    });

    test('configure declares --until and --untilTimeoutMs options', () {
      final parser = ArgParser();
      DuskTapCommand().configure(parser);
      expect(parser.options.keys,
          containsAll(<String>['until', 'untilTimeoutMs']));
    });

    test('handle forwards --until and --untilTimeoutMs to ext.dusk.tap',
        () async {
      final ctx = _StubContext(
        input: MapInput(const {
          'ref': 'e5',
          'until': 'Welcome back',
          'untilTimeoutMs': '5000',
        }),
        output: BufferedOutput(),
        response: const {'ref': 'e5', 'untilMatched': true},
      );
      final exit = await DuskTapCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastParams, containsPair('until', 'Welcome back'));
      expect(ctx.lastParams, containsPair('untilTimeoutMs', '5000'));
    });

    test('handle omits until params when --until is absent', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );
      await DuskTapCommand().handle(ctx);
      expect(ctx.lastParams!.containsKey('until'), isFalse);
      expect(ctx.lastParams!.containsKey('untilTimeoutMs'), isFalse);
    });

    test('handle returns 1 when --ref is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await DuskTapCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns 1 when --ref is empty', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': ''}),
        output: BufferedOutput(),
      );
      final exit = await DuskTapCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('--json prints the envelope instead of the summary', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'json': true}),
        output: output,
        response: const {
          'ref': 'e7',
          'effect': {'kind': 'treeChanged', 'changed': true},
        },
      );

      final exit = await DuskTapCommand().handle(ctx);

      expect(exit, equals(0));
      expect(output.content, contains('"kind":"treeChanged"'));
      expect(output.content, isNot(contains('Tapped e7')));
    });

    test('the summary names a tap that changed nothing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
        response: const {
          'ref': 'e7',
          'effect': {'kind': 'treeChanged', 'changed': false},
        },
      );

      await DuskTapCommand().handle(ctx);

      expect(output.content, contains('no observable change'));
    });

    test('handle surfaces the frame-production banner beside the success line',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
        response: const {
          'ref': 'e7',
          'warnings': {
            'framesEnabled': false,
            'lifecycleState': 'hidden',
            'hint': 'The engine is not producing frames...',
          },
        },
      );

      final exit = await DuskTapCommand().handle(ctx);

      expect(exit, equals(0));
      // The default path prints `✓ Tapped e7` and discards the envelope, so
      // a tap that could not possibly land would otherwise read as a success.
      expect(output.content, contains('Tapped e7'));
      expect(output.content, contains('not producing frames'));
    });
  });
}
