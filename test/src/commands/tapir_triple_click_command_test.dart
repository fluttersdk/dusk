import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dowel/dowel.dart';

import 'package:tapir/src/commands/tapir_triple_click_command.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    this._response = const {},
  }) : super.bare(input, output);

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
  group('TapirTripleClickCommand', () {
    test('name is tapir:triple_click', () {
      expect(TapirTripleClickCommand().name, equals('tapir:triple_click'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirTripleClickCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref + gate + includeSnapshot flags', () {
      final parser = ArgParser();
      TapirTripleClickCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>[
          'ref',
          'includeSnapshot',
          'checkStable',
          'checkReceivesEvents',
        ]),
      );
    });

    test('handle forwards --ref + flags to ext.tapir.triple_click', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
      );
      final exit = await TapirTripleClickCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.triple_click'));
      expect(ctx.lastParams, containsPair('ref', 'e7'));
      expect(ctx.lastParams, containsPair('checkStable', 'true'));
      expect(ctx.lastParams, containsPair('checkReceivesEvents', 'true'));
    });

    test('handle returns exit=1 with error when --ref is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(input: MapInput(const {}), output: output);
      final exit = await TapirTripleClickCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test(
      'handle returns exit=1 with error when --ref is empty string',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': ''}),
          output: output,
        );
        final exit = await TapirTripleClickCommand().handle(ctx);
        expect(exit, equals(1));
      },
    );

    test('handle prints JSON when --includeSnapshot=true', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'includeSnapshot': true}),
        output: output,
        response: const {'ref': 'e7', 'snapshot': '- button "x"'},
      );
      await TapirTripleClickCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('includeSnapshot', 'true'));
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['ref'], equals('e7'));
      expect(decoded['snapshot'], contains('button'));
    });

    test('handle prints success line when --includeSnapshot=false', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
      );
      await TapirTripleClickCommand().handle(ctx);
      expect(output.content, contains('Triple-clicked e7'));
    });

    test('handle honours --no-checkStable opt-out', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'checkStable': false}),
        output: BufferedOutput(),
      );
      await TapirTripleClickCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('checkStable', 'false'));
    });
  });
}
