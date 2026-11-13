import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dowel/dowel.dart';

import 'package:tapir/src/commands/tapir_focus_command.dart';

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
  group('TapirFocusCommand', () {
    test('name is tapir:focus', () {
      expect(TapirFocusCommand().name, equals('tapir:focus'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirFocusCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref + --includeSnapshot', () {
      final parser = ArgParser();
      TapirFocusCommand().configure(parser);
      expect(
          parser.options.keys, containsAll(<String>['ref', 'includeSnapshot']));
    });

    test('handle forwards --ref to ext.tapir.focus', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e1'}),
        output: BufferedOutput(),
      );
      final exit = await TapirFocusCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.focus'));
      expect(ctx.lastParams, containsPair('ref', 'e1'));
    });

    test('handle returns exit=1 when --ref is missing', () async {
      final ctx =
          _StubContext(input: MapInput(const {}), output: BufferedOutput());
      expect(await TapirFocusCommand().handle(ctx), equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns exit=1 when --ref is empty string', () async {
      final ctx = _StubContext(
          input: MapInput(const {'ref': ''}), output: BufferedOutput());
      expect(await TapirFocusCommand().handle(ctx), equals(1));
    });

    test('handle emits JSON when --includeSnapshot=true', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e1', 'includeSnapshot': true}),
        output: output,
        response: const {'ref': 'e1', 'focused': true},
      );
      await TapirFocusCommand().handle(ctx);
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['focused'], isTrue);
    });

    test('handle emits "Focused" success by default', () async {
      final output = BufferedOutput();
      final ctx =
          _StubContext(input: MapInput(const {'ref': 'e1'}), output: output);
      await TapirFocusCommand().handle(ctx);
      expect(output.content, contains('Focused e1'));
    });
  });
}
