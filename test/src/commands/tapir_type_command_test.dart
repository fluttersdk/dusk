import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_type_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
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
  group('TapirTypeCommand', () {
    test('name is tapir:type', () {
      expect(TapirTypeCommand().name, equals('tapir:type'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirTypeCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirTypeCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.type with ref and text', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3', 'text': 'hello'}),
        output: BufferedOutput(),
      );

      await TapirTypeCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.type'));
      expect(ctx.lastParams, containsPair('ref', 'e3'));
      expect(ctx.lastParams, containsPair('text', 'hello'));
    });

    test('handle returns 1 and prints error when ref is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'text': 'hello'}),
        output: output,
      );

      final code = await TapirTypeCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('ref'));
    });

    test('handle returns 1 and prints error when text is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3'}),
        output: output,
      );

      final code = await TapirTypeCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('text'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3', 'text': 'hello'}),
        output: BufferedOutput(),
      );

      expect(await TapirTypeCommand().handle(ctx), equals(0));
    });

    group('.handle() outcome summary', () {
      test('unverified effect prints what the field holds and exits 1',
          () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e3', 'text': '12ab'}),
          output: output,
          response: const {
            'effect': {'kind': 'text', 'verified': false, 'value': '12'},
          },
        );

        final code = await TapirTypeCommand().handle(ctx);

        expect(code, equals(1));
        expect(output.content, contains('[ERROR]'));
        expect(output.content, contains('e3'));
        expect(output.content, contains('"12"'));
        expect(output.content, contains('"12ab"'));
        expect(output.content, isNot(contains('Typed into')));
      });

      test('verified effect keeps the plain summary and exits 0', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e3', 'text': 'hello'}),
          output: output,
          response: const {
            'effect': {'kind': 'text', 'verified': true, 'value': 'hello'},
          },
        );

        final code = await TapirTypeCommand().handle(ctx);

        expect(code, equals(0));
        expect(output.content, contains('Typed into e3'));
      });

      test('a nearest-match target names the field that was written', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e3', 'text': 'hello'}),
          output: output,
          response: const {
            'effect': {
              'kind': 'text',
              'verified': true,
              'value': 'hello',
              'target': {
                'matchKind': 'nearest',
                'label': 'Name',
                'rect': {'x': 0.0, 'y': 48.0, 'width': 800.0, 'height': 24.0},
              },
            },
          },
        );

        final code = await TapirTypeCommand().handle(ctx);

        expect(code, equals(0));
        expect(output.content, contains('nearest'));
        expect(output.content, contains('"Name"'));
        expect(output.content, contains('(0, 48, 800x24)'));
        expect(output.content, contains('Typed into e3'));
      });

      test('an overlapping target keeps the plain summary', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e3', 'text': 'hello'}),
          output: output,
          response: const {
            'effect': {
              'kind': 'text',
              'verified': true,
              'value': 'hello',
              'target': {
                'matchKind': 'overlap',
                'label': 'Name',
                'rect': {'x': 0.0, 'y': 48.0, 'width': 800.0, 'height': 24.0},
              },
            },
          },
        );

        await TapirTypeCommand().handle(ctx);

        expect(output.content, isNot(contains('nearest')));
      });

      test('--json prints the envelope untouched for an unverified effect',
          () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e3', 'text': '12ab', 'json': true}),
          output: output,
          response: const {
            'effect': {'kind': 'text', 'verified': false, 'value': '12'},
          },
        );

        final code = await TapirTypeCommand().handle(ctx);

        expect(code, equals(0));
        expect(output.content, contains('"verified":false'));
        expect(output.content, isNot(contains('[ERROR]')));
      });
    });

    test('--snapshot passes the mode through and prints the text after',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e3', 'text': 'hi', 'snapshot': 'full'}),
        output: output,
        response: const {
          'text': 'hi',
          'snapshot': '- textbox "Name": "hi" [ref=e3]\n',
        },
      );

      final code = await TapirTypeCommand().handle(ctx);

      expect(code, equals(0));
      expect(ctx.lastParams, containsPair('snapshot', 'full'));
      expect(ctx.lastParams!.containsKey('includeSnapshot'), isFalse);
      final String content = output.content;
      expect(content.indexOf('Typed into e3'), greaterThanOrEqualTo(0));
      expect(
        content.indexOf('Typed into e3'),
        lessThan(content.indexOf('- textbox "Name": "hi" [ref=e3]')),
      );
    });
  });
}
