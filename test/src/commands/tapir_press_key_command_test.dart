import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_press_key_command.dart';

class _StubContext extends DowelContext {
  _StubContext({required DowelInput input, required DowelOutput output})
    : _response = const {},
      super.bare(input, output);

  final Map<String, dynamic> _response;
  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('TapirPressKeyCommand', () {
    test('name is tapir:press_key', () {
      expect(TapirPressKeyCommand().name, equals('tapir:press_key'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirPressKeyCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --key and --modifiers', () {
      final parser = ArgParser();
      TapirPressKeyCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['key', 'modifiers']));
    });

    test('handle forwards --key only when modifiers omitted', () async {
      final ctx = _StubContext(
        input: MapInput(const {'key': 'Enter'}),
        output: BufferedOutput(),
      );
      await TapirPressKeyCommand().handle(ctx);
      expect(ctx.lastMethod, equals('ext.tapir.press_key'));
      expect(ctx.lastParams, containsPair('key', 'Enter'));
    });

    test('handle forwards --key + --modifiers when both present', () async {
      final ctx = _StubContext(
        input: MapInput(const {'key': 'a', 'modifiers': 'ctrl,shift'}),
        output: BufferedOutput(),
      );
      await TapirPressKeyCommand().handle(ctx);
      expect(
        ctx.lastParams,
        allOf(
          containsPair('key', 'a'),
          containsPair('modifiers', 'ctrl,shift'),
        ),
      );
    });

    test('handle returns 1 when --key is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await TapirPressKeyCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    group('.handle() outcome summary', () {
      test('--modifiers presses without a not-applied notice', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'key': 'a', 'modifiers': 'ctrl,shift'}),
          output: output,
        );

        final exit = await TapirPressKeyCommand().handle(ctx);

        expect(exit, equals(0));
        expect(output.content, isNot(contains('[ERROR]')));
        expect(output.content, isNot(contains('not applied')));
        expect(output.content, contains('Pressed a'));
      });

      test('--modifiers help names every accepted modifier', () {
        final parser = ArgParser();
        TapirPressKeyCommand().configure(parser);

        expect(
          parser.options['modifiers']!.help,
          allOf(
            contains('control'),
            contains('ctrl'),
            contains('shift'),
            contains('alt'),
            contains('meta'),
          ),
        );
      });

      test('no notice without --modifiers', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'key': 'Enter'}),
          output: output,
        );

        await TapirPressKeyCommand().handle(ctx);

        expect(output.content, isNot(contains('not applied')));
      });
    });
  });
}
