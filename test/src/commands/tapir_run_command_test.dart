import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_resize_command.dart';
import 'package:tapir/src/commands/tapir_run_command.dart';

/// A connected verb that records what it was handed and answers [exitCode].
class _FakeVerb extends DowelCommand {
  _FakeVerb(
    this.name, {
    this.exitCode = 0,
    this.throws,
  });

  @override
  final String name;

  final int exitCode;
  final Object? throws;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  String get description => 'Fake verb for tapir:run tests.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('ref');
    parser.addOption('text');
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    calls.add(<String, Object?>{
      'ref': ctx.input.option('ref'),
      'text': ctx.input.option('text'),
      'connected': ctx.vmClient != null,
    });
    final Object? error = throws;
    if (error != null) throw error;
    ctx.output.writeln('$name ran ${ctx.input.option('ref')}');
    return exitCode;
  }
}

void main() {
  group('TapirRunCommand', () {
    late _FakeVerb tap;
    late _FakeVerb fill;
    late _FakeVerb broken;
    late _FakeVerb missing;
    late _FakeVerb mandatory;
    late DowelRegistry registry;

    setUp(() {
      tap = _FakeVerb('tapir:tap');
      fill = _FakeVerb('tapir:fill');
      broken = _FakeVerb('tapir:broken', exitCode: 4);
      missing = _FakeVerb(
        'tapir:missing',
        throws: const ExtensionNotRegisteredException('ext.tapir.missing'),
      );
      // An argparse `mandatory: true` option that was left out surfaces as an
      // ArgumentError (an Error, not an Exception) when the verb reads it.
      mandatory = _FakeVerb(
        'tapir:mandatory',
        throws: ArgumentError('Option ref is mandatory.'),
      );
      registry = DowelRegistry()
        ..registerAll(<DowelCommand>[
          TapirRunCommand(),
          tap,
          fill,
          broken,
          missing,
          mandatory,
          TapirResizeCommand(),
        ]);
    });

    DowelContext cliContext(List<String> argv, BufferedOutput output) {
      final ArgParser parser = ArgParser();
      TapirRunCommand().configure(parser);
      return DowelContext.connected(
        ArgvInput.parse(parser, argv),
        output,
        VmServiceClient('ws://127.0.0.1:1/ws'),
        registry: registry,
      );
    }

    test('name is tapir:run and boot is connected', () {
      expect(TapirRunCommand().name, 'tapir:run');
      expect(TapirRunCommand().boot, CommandBoot.connected);
    });

    test('runs three steps in order and prints a line per step', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(
          <String>[
            'tap --ref=e5',
            'fill --ref=q1 --text=hi',
            'tap --ref=e6',
          ],
          output,
        ),
      );

      expect(exit, 0);
      expect(
        tap.calls.map((Map<String, Object?> c) => c['ref']),
        <String>['e5', 'e6'],
      );
      expect(fill.calls.single['text'], 'hi');
      expect(tap.calls.first['connected'], isTrue);
      expect(output.content, contains('[1/3] tap --ref=e5 ok'));
      expect(output.content, contains('[2/3] fill --ref=q1 --text=hi ok'));
      expect(output.content, contains('[3/3] tap --ref=e6 ok'));
      // The last step's own output follows the step lines.
      expect(output.content.trimRight(), endsWith('tapir:tap ran e6'));
    });

    test('stops at the first failing step and exits with its code', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(
          <String>[
            'tap --ref=e5',
            'broken --ref=e7',
            'tap --ref=e6',
          ],
          output,
        ),
      );

      expect(exit, 4);
      expect(tap.calls, hasLength(1));
      expect(
          output.content, contains('step 2 failed (exit 4): broken --ref=e7'));
      expect(output.content, contains('tapir:broken ran e7'));
      expect(output.content, isNot(contains('[3/3]')));
    });

    test('--continue runs every step and exits with the first failure',
        () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(
          <String>[
            'broken --ref=e7',
            'tap --ref=e5',
            'tap --ref=e6',
            '--continue',
          ],
          output,
        ),
      );

      expect(exit, 4);
      expect(tap.calls, hasLength(2));
      expect(output.content, contains('[1/3] broken --ref=e7 failed (exit 4)'));
      expect(output.content, contains('[3/3] tap --ref=e6 ok'));
      expect(output.content, contains('step 1 failed (exit 4)'));
    });

    test('rejects a nested tapir:run step', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(<String>['run tap'], output),
      );

      expect(exit, isNot(0));
      expect(output.content, contains('step 1 failed'));
      expect(output.content, contains('tapir:run cannot be nested'));
    });

    test('rejects a verb that does not run on the connected app', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(<String>['resize --width=400 --height=800'], output),
      );

      expect(exit, isNot(0));
      expect(output.content, contains('tapir:resize'));
      expect(output.content, contains('does not run on the connected app'));
    });

    test('rejects an unknown verb', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(<String>['nope'], output),
      );

      expect(exit, 1);
      expect(output.content, contains('unknown verb tapir:nope'));
    });

    test('reports an option the verb does not declare as that step failing',
        () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(<String>['tap --bogus=1'], output),
      );

      expect(exit, 1);
      expect(tap.calls, isEmpty);
      expect(output.content, contains('step 1 failed (exit 1)'));
    });

    test('keeps a quoted value with a space as one token', () async {
      final int exit = await TapirRunCommand().handle(
        cliContext(
          <String>[
            'fill --ref=q1 --text="a b"',
            "fill --ref=q2 --text='c d'",
            r'fill --ref=q3 --text=e\ f',
            r'fill --ref=q4 --text="say \"hi\""',
          ],
          BufferedOutput(),
        ),
      );

      expect(exit, 0);
      expect(
        fill.calls.map((Map<String, Object?> c) => c['text']),
        <String>['a b', 'c d', 'e f', 'say "hi"'],
      );
    });

    test('reports an unterminated quote as that step failing', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(<String>['fill --text="a b'], output),
      );

      expect(exit, 1);
      expect(fill.calls, isEmpty);
      expect(output.content, contains('unterminated quote'));
    });

    test('a verb that throws an Error fails its own step, not the batch',
        () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(<String>['mandatory', 'tap --ref=e2', '--continue'], output),
      );

      expect(exit, 3);
      expect(output.content, contains('mandatory'));
      expect(output.content, contains('Option ref is mandatory'));
      expect(output.content, contains('step 1 failed (exit 3)'));
      expect(tap.calls, hasLength(1), reason: '--continue still runs step 2');
    });

    test('maps an extension that is not registered yet to exit 75', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(<String>['missing --ref=e1'], output),
      );

      expect(exit, DowelCommand.exitTryAgain);
      expect(output.content, contains('ext.tapir.missing is not registered'));
    });

    test('runs the same steps from an MCP steps list', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        DowelContext.connected(
          MapInput(<String, dynamic>{
            'steps': <dynamic>[
              'tap --ref=e5',
              'fill --ref=q1 --text="a b"',
            ],
          }),
          output,
          VmServiceClient('ws://127.0.0.1:1/ws'),
          registry: registry,
        ),
      );

      expect(exit, 0);
      expect(tap.calls.single['ref'], 'e5');
      expect(fill.calls.single['text'], 'a b');
      expect(output.content, contains('[2/2] fill --ref=q1 --text="a b" ok'));
    });

    test('honours continue from an MCP call', () async {
      final int exit = await TapirRunCommand().handle(
        DowelContext.connected(
          MapInput(<String, dynamic>{
            'steps': <dynamic>[
              'broken',
              'tap --ref=e5',
            ],
            'continue': true,
          }),
          BufferedOutput(),
          VmServiceClient('ws://127.0.0.1:1/ws'),
          registry: registry,
        ),
      );

      expect(exit, 4);
      expect(tap.calls, hasLength(1));
    });

    test('fails without steps', () async {
      final BufferedOutput output = BufferedOutput();
      final int exit = await TapirRunCommand().handle(
        cliContext(const <String>[], output),
      );

      expect(exit, 1);
      expect(output.content, contains('No steps'));
    });
  });
}
