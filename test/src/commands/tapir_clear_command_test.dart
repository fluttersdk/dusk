import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dowel/dowel.dart';

import 'package:tapir/src/commands/tapir_clear_command.dart';

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
  group('TapirClearCommand', () {
    test('name is tapir:clear', () {
      expect(TapirClearCommand().name, equals('tapir:clear'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirClearCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref + --includeSnapshot', () {
      final parser = ArgParser();
      TapirClearCommand().configure(parser);
      expect(
          parser.options.keys, containsAll(<String>['ref', 'includeSnapshot']));
    });

    test('handle forwards --ref to ext.tapir.clear', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e1'}),
        output: BufferedOutput(),
      );
      final exit = await TapirClearCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.clear'));
      expect(ctx.lastParams, containsPair('ref', 'e1'));
    });

    test('handle returns exit=1 when --ref is missing', () async {
      final ctx =
          _StubContext(input: MapInput(const {}), output: BufferedOutput());
      expect(await TapirClearCommand().handle(ctx), equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns exit=1 when --ref is empty string', () async {
      final ctx = _StubContext(
          input: MapInput(const {'ref': ''}), output: BufferedOutput());
      expect(await TapirClearCommand().handle(ctx), equals(1));
    });

    test('handle emits JSON when --includeSnapshot=true', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e1', 'includeSnapshot': true}),
        output: output,
        response: const {'ref': 'e1', 'cleared': true},
      );
      await TapirClearCommand().handle(ctx);
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['cleared'], isTrue);
    });

    test('handle emits "Cleared" success by default', () async {
      final output = BufferedOutput();
      final ctx =
          _StubContext(input: MapInput(const {'ref': 'e1'}), output: output);
      await TapirClearCommand().handle(ctx);
      expect(output.content, contains('Cleared e1'));
    });
  });
}
