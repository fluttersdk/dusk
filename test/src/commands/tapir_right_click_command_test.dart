import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dowel/dowel.dart';

import 'package:tapir/src/commands/tapir_right_click_command.dart';

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
  group('TapirRightClickCommand', () {
    test('name is tapir:right_click', () {
      expect(TapirRightClickCommand().name, equals('tapir:right_click'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirRightClickCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref + gate + includeSnapshot flags', () {
      final parser = ArgParser();
      TapirRightClickCommand().configure(parser);
      expect(
          parser.options.keys,
          containsAll(<String>[
            'ref',
            'includeSnapshot',
            'checkStable',
            'checkReceivesEvents'
          ]));
    });

    test('handle forwards --ref + flags to ext.tapir.right_click', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
      );
      final exit = await TapirRightClickCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.right_click'));
      expect(ctx.lastParams, containsPair('ref', 'e7'));
      expect(ctx.lastParams, containsPair('checkStable', 'true'));
    });

    test('handle returns exit=1 when --ref is missing', () async {
      final ctx =
          _StubContext(input: MapInput(const {}), output: BufferedOutput());
      final exit = await TapirRightClickCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns exit=1 when --ref is empty', () async {
      final ctx = _StubContext(
          input: MapInput(const {'ref': ''}), output: BufferedOutput());
      expect(await TapirRightClickCommand().handle(ctx), equals(1));
    });

    test('handle emits JSON envelope when --includeSnapshot=true', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'includeSnapshot': true}),
        output: output,
        response: const {'ref': 'e7', 'snapshot': '- menu'},
      );
      await TapirRightClickCommand().handle(ctx);
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['snapshot'], equals('- menu'));
    });

    test('handle emits "Right-clicked" success line by default', () async {
      final output = BufferedOutput();
      final ctx =
          _StubContext(input: MapInput(const {'ref': 'e7'}), output: output);
      await TapirRightClickCommand().handle(ctx);
      expect(output.content, contains('Right-clicked e7'));
    });

    test('handle honours --no-checkReceivesEvents opt-out', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'checkReceivesEvents': false}),
        output: BufferedOutput(),
      );
      await TapirRightClickCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('checkReceivesEvents', 'false'));
    });
  });
}
