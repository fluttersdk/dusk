import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_set_checkbox_command.dart';

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
  group('TapirSetCheckboxCommand', () {
    test('name is tapir:set_checkbox', () {
      expect(TapirSetCheckboxCommand().name, equals('tapir:set_checkbox'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirSetCheckboxCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirSetCheckboxCommand().description, isNotEmpty);
    });

    test('configure declares --ref and --value options', () {
      final parser = ArgParser();
      TapirSetCheckboxCommand().configure(parser);
      expect(parser.options.keys, containsAll(<String>['ref', 'value']));
    });

    test('handle calls ext.tapir.set_checkbox', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'true'}),
        output: BufferedOutput(),
        response: const {
          'ref': 'e5',
          'previousValue': false,
          'value': true,
          'toggled': true,
        },
      );

      await TapirSetCheckboxCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.tapir.set_checkbox'));
    });

    test('handle forwards --ref and --value params', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'true'}),
        output: BufferedOutput(),
        response: const {
          'ref': 'e5',
          'previousValue': false,
          'value': true,
          'toggled': true,
        },
      );

      await TapirSetCheckboxCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('ref', 'e5'));
      expect(ctx.lastParams, containsPair('value', 'true'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'false'}),
        output: BufferedOutput(),
        response: const {
          'ref': 'e5',
          'previousValue': true,
          'value': false,
          'toggled': true,
        },
      );

      expect(await TapirSetCheckboxCommand().handle(ctx), equals(0));
    });

    test('a verified toggle exits 0 and prints the success line', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'true'}),
        output: output,
        response: const {
          'ref': 'e5',
          'previousValue': false,
          'value': true,
          'toggled': true,
          'effect': {
            'kind': 'checked',
            'verified': true,
            'before': false,
            'after': true,
          },
        },
      );

      expect(await TapirSetCheckboxCommand().handle(ctx), equals(0));
      expect(output.content, contains('Checkbox e5 set to true'));
    });

    test(
      'an unverified toggle exits 1 and names the value read back',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'value': 'true'}),
          output: output,
          response: const {
            'ref': 'e5',
            'previousValue': false,
            'value': true,
            'toggled': true,
            'effect': {
              'kind': 'checked',
              'verified': false,
              'before': false,
              'after': false,
            },
          },
        );

        expect(await TapirSetCheckboxCommand().handle(ctx), equals(1));
        expect(
          output.content,
          contains(
            'Set checkbox not verified: e5 reads false after the tap, not true',
          ),
        );
        expect(output.content, isNot(contains('Checkbox e5 set to true')));
      },
    );

    test('a mixed checkbox that was set says it started mixed', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'true'}),
        output: output,
        response: const {
          'ref': 'e5',
          'previousValue': null,
          'value': true,
          'toggled': true,
          'effect': {
            'kind': 'checked',
            'verified': true,
            'before': null,
            'after': true,
          },
        },
      );

      expect(await TapirSetCheckboxCommand().handle(ctx), equals(0));
      expect(output.content, contains('Checkbox e5 set to true'));
      expect(output.content, contains('was mixed'));
    });

    test('--json prints the whole envelope', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'value': 'true', 'json': true}),
        output: output,
        response: const {
          'ref': 'e5',
          'previousValue': false,
          'value': true,
          'toggled': true,
          'effect': {
            'kind': 'checked',
            'verified': false,
            'before': false,
            'after': false,
          },
        },
      );

      await TapirSetCheckboxCommand().handle(ctx);

      expect(output.content, contains('"previousValue":false'));
      expect(output.content, contains('"verified":false'));
      expect(output.content, isNot(contains('not verified')));
    });

    test('--includeSnapshot help says no snapshot is embedded', () {
      final parser = ArgParser();
      TapirSetCheckboxCommand().configure(parser);
      final help = parser.options['includeSnapshot']!.help!;
      expect(help, contains('never embeds a snapshot'));
    });
  });
}
