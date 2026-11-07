import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_fill_command.dart';

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
  group('DuskFillCommand', () {
    test('name is dusk:fill', () {
      expect(DuskFillCommand().name, equals('dusk:fill'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskFillCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref and --text options', () {
      final parser = ArgParser();
      DuskFillCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['ref', 'text']));
    });

    test('handle forwards --ref and --text to ext.dusk.fill', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'text': 'hello'}),
        output: BufferedOutput(),
      );
      final exit = await DuskFillCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.fill'));
      expect(ctx.lastParams, containsPair('ref', 'e5'));
      expect(ctx.lastParams, containsPair('text', 'hello'));
    });

    test('handle returns 1 when --ref is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {'text': 'hello'}),
        output: BufferedOutput(),
      );
      final exit = await DuskFillCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    group('.handle() outcome summary', () {
      test('unverified effect prints what the field holds and exits 1',
          () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'text': 'hello'}),
          output: output,
          response: const {
            'effect': {'kind': 'text', 'verified': false, 'value': 'hel'},
          },
        );

        final exit = await DuskFillCommand().handle(ctx);

        expect(exit, equals(1));
        expect(output.content, contains('[ERROR]'));
        expect(output.content, contains('e5'));
        expect(output.content, contains('"hel"'));
        expect(output.content, contains('"hello"'));
        expect(output.content, isNot(contains('Filled')));
      });

      test('verified effect keeps the plain summary and exits 0', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'text': 'hello'}),
          output: output,
          response: const {
            'effect': {'kind': 'text', 'verified': true, 'value': 'hello'},
          },
        );

        final exit = await DuskFillCommand().handle(ctx);

        expect(exit, equals(0));
        expect(output.content, contains('Filled e5'));
      });

      test('a nearest-match target names the field that was written', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'text': 'hello'}),
          output: output,
          response: const {
            'effect': {
              'kind': 'text',
              'verified': true,
              'value': 'hello',
              'target': {
                'matchKind': 'nearest',
                'label': null,
                'rect': {'x': 10.5, 'y': 48.0, 'width': 200.0, 'height': 24.0},
              },
            },
          },
        );

        final exit = await DuskFillCommand().handle(ctx);

        expect(exit, equals(0));
        expect(output.content, contains('nearest'));
        expect(output.content, contains('(10.5, 48, 200x24)'));
        expect(output.content, contains('Filled e5'));
      });

      test('an overlapping target keeps the plain summary', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'text': 'hello'}),
          output: output,
          response: const {
            'effect': {
              'kind': 'text',
              'verified': true,
              'value': 'hello',
              'target': {
                'matchKind': 'overlap',
                'label': 'Name',
                'rect': {'x': 0.0, 'y': 0.0, 'width': 200.0, 'height': 24.0},
              },
            },
          },
        );

        await DuskFillCommand().handle(ctx);

        expect(output.content, isNot(contains('nearest')));
      });

      test('--json prints the envelope untouched for an unverified effect',
          () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'text': 'hello', 'json': true}),
          output: output,
          response: const {
            'effect': {'kind': 'text', 'verified': false, 'value': 'hel'},
          },
        );

        final exit = await DuskFillCommand().handle(ctx);

        expect(exit, equals(0));
        expect(output.content, contains('"verified":false'));
        expect(output.content, isNot(contains('[ERROR]')));
      });
    });

    test('--snapshot passes the mode through and prints the text after',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'text': 'hi', 'snapshot': 'diff'}),
        output: output,
        response: const {
          'ref': 'e5',
          'filled': true,
          'snapshot': '+ - textbox "Name": "hi" [ref=e5]\n'
              '(1 of 4 lines changed)',
          'snapshotMode': 'diff',
        },
      );

      final exit = await DuskFillCommand().handle(ctx);

      expect(exit, equals(0));
      expect(ctx.lastParams, containsPair('snapshot', 'diff'));
      expect(ctx.lastParams!.containsKey('includeSnapshot'), isFalse);
      final String content = output.content;
      expect(content, isNot(contains('"snapshotMode"')));
      expect(
        content.indexOf('Filled e5'),
        lessThan(content.indexOf('(1 of 4 lines changed)')),
      );
      expect(content.indexOf('Filled e5'), greaterThanOrEqualTo(0));
    });
  });
}
