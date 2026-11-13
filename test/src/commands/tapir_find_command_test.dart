import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_find_command.dart';

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
  group('TapirFindCommand', () {
    test('name is tapir:find', () {
      expect(TapirFindCommand().name, equals('tapir:find'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirFindCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --text / --semanticsLabel / --key options', () {
      final parser = ArgParser();
      TapirFindCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>['text', 'semanticsLabel', 'key']),
      );
    });

    test('handle forwards --text only', () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'Submit'}),
        output: BufferedOutput(),
        response: const {'ref': 'q1', 'matched': true},
      );
      await TapirFindCommand().handle(ctx);
      expect(ctx.lastMethod, equals('ext.tapir.find'));
      expect(ctx.lastParams, containsPair('text', 'Submit'));
    });

    test('handle forwards --semanticsLabel only', () async {
      final ctx = _StubContext(
        input: MapInput(const {'semanticsLabel': 'Open navigation menu'}),
        output: BufferedOutput(),
      );
      await TapirFindCommand().handle(ctx);
      expect(
        ctx.lastParams,
        containsPair('semanticsLabel', 'Open navigation menu'),
      );
    });

    test('handle forwards --key only', () async {
      final ctx = _StubContext(
        input: MapInput(const {'key': 'monitor-row-7'}),
        output: BufferedOutput(),
      );
      await TapirFindCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('key', 'monitor-row-7'));
    });

    test('handle forwards every supplied predicate', () async {
      final ctx = _StubContext(
        input: MapInput(const {
          'text': 'Submit',
          'semanticsLabel': 'Submit form',
          'key': 'submit-btn',
        }),
        output: BufferedOutput(),
      );
      await TapirFindCommand().handle(ctx);
      expect(
        ctx.lastParams,
        equals({
          'text': 'Submit',
          'semanticsLabel': 'Submit form',
          'key': 'submit-btn',
        }),
      );
    });

    test('handle returns 1 when no predicate is supplied', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await TapirFindCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });
    test('handle forwards --within so the query keeps its scope', () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'Monitors', 'within': 'e7'}),
        output: BufferedOutput(),
      );

      await TapirFindCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('within', 'e7'));
    });
  });
}
