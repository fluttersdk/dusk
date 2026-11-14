import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_snap_command.dart';

import '../cdp/fake_cdp_server.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    this._response = const {},
    this._retryResponse,
  }) : super.bare(input, output);

  final Map<String, dynamic> _response;
  final Map<String, dynamic>? _retryResponse;
  String? lastMethod;
  Map<String, dynamic>? lastParams;
  int calls = 0;

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastMethod = method;
    lastParams = params;
    calls++;
    if (calls > 1 && _retryResponse != null) return _retryResponse as T;
    return _response as T;
  }
}

void main() {
  group('TapirSnapCommand on a hidden web tab', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tapir_snap_web_');
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      await tempDir.delete(recursive: true);
    });

    test(
      'brings the page to front once and prints the re-taken snapshot',
      () async {
        final List<String> frames = <String>[];
        final FakeCdpServer server = await FakeCdpServer.start(
          pageUrl: 'http://localhost:5123/',
          handlers: {
            'Page.bringToFront': (Map<String, dynamic> _) async {
              frames.add('Page.bringToFront');
              return <String, dynamic>{};
            },
          },
        );
        addTearDown(server.stop);
        final Directory stateDir = Directory('${tempDir.path}/.dowel');
        await stateDir.create(recursive: true);
        await File(
          '${stateDir.path}/state.json',
        ).writeAsString(jsonEncode({'cdpPort': server.port, 'webPort': 5123}));
        StateFile.debugHomeOverride = tempDir.path;

        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: const {
            'snapshot': '- stale',
            'warnings': {
              'framesEnabled': false,
              'lifecycleState': 'hidden',
              'platform': 'web',
            },
          },
          retryResponse: const {'snapshot': '- button "Save" [ref=e1]'},
        );

        final exit = await TapirSnapCommand().handle(ctx);

        expect(exit, equals(0));
        expect(frames, equals(<String>['Page.bringToFront']));
        expect(ctx.calls, equals(2));
        expect(output.content, contains('[ref=e1]'));
        expect(output.content, isNot(contains('- stale')));
        expect(output.content, isNot(contains('not producing frames')));
      },
    );
  });

  group('TapirSnapCommand', () {
    test('name is tapir:snap', () {
      expect(TapirSnapCommand().name, equals('tapir:snap'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirSnapCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --depth option', () {
      final parser = ArgParser();
      TapirSnapCommand().configure(parser);
      expect(parser.options.keys, contains('depth'));
    });

    test(
      'handle calls ext.tapir.snap with no params when --depth omitted',
      () async {
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: BufferedOutput(),
          response: const {'snapshot': '- button "Foo" [ref=e1]'},
        );
        final exit = await TapirSnapCommand().handle(ctx);
        expect(exit, equals(0));
        expect(ctx.lastMethod, equals('ext.tapir.snap'));
        // Caller passed nothing; command may add default flags (e.g.
        // includeEnrichers) so we only assert the caller-supplied keys
        // are NOT present.
        expect(ctx.lastParams!.containsKey('depth'), isFalse);
      },
    );

    test('handle forwards --depth to ext.tapir.snap when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'depth': '3'}),
        output: BufferedOutput(),
        response: const {'snapshot': ''},
      );
      await TapirSnapCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('depth', '3'));
    });

    test('handle prints the snapshot string to ctx.output', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {
          'snapshot': '- text "Hello"\n- button "Click" [ref=e1]',
        },
      );
      await TapirSnapCommand().handle(ctx);
      expect(output.content, contains('Hello'));
      expect(output.content, contains('[ref=e1]'));
    });

    test(
      'handle surfaces a renderErrors banner alongside the snapshot',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: const {
            'snapshot': '- button "Save" [ref=e1]',
            'renderErrors': {
              'count': 2,
              'recent': [
                {
                  'type': 'FlutterError',
                  'message': 'Incorrect use of ParentDataWidget.',
                },
              ],
              'hint':
                  'Run tapir:exceptions (CLI) or tapir_exceptions (MCP) for '
                  'full messages + stack traces.',
            },
          },
        );
        final exit = await TapirSnapCommand().handle(ctx);
        expect(exit, equals(0));
        // The banner is surfaced (it routes to stderr via ctx.output.error in
        // production; BufferedOutput merges that channel into content for the
        // assertion).
        expect(output.content, contains('2 render error(s) captured'));
        expect(output.content, contains('Incorrect use of ParentDataWidget.'));
        // The snapshot payload is still emitted.
        expect(output.content, contains('[ref=e1]'));
      },
    );

    test('handle surfaces the frame-production banner', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {
          'snapshot': '- button "Save" [ref=e1]',
          'warnings': {
            'framesEnabled': false,
            'lifecycleState': 'hidden',
            'hint': 'The engine is not producing frames...',
          },
        },
      );

      final exit = await TapirSnapCommand().handle(ctx);

      expect(exit, equals(0));
      // stdout carries only the tree, so without this banner the one field
      // that says the tree is untrustworthy would be dropped on the floor.
      expect(output.content, contains('not producing frames'));
      expect(output.content, contains('lifecycle: hidden'));
      expect(output.content, contains('[ref=e1]'));
    });

    test('handle stays quiet when the engine is healthy', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'snapshot': '- button "Save" [ref=e1]'},
      );

      await TapirSnapCommand().handle(ctx);

      expect(output.content, isNot(contains('not producing frames')));
    });

    test(
      'handle falls back to JSON encode when response has no snapshot key',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: const {'note': 'no snapshot key'},
        );
        await TapirSnapCommand().handle(ctx);
        expect(output.content, contains('no snapshot key'));
      },
    );
    test('configure declares --json defaulting to off', () {
      final parser = ArgParser();
      TapirSnapCommand().configure(parser);
      expect(parser.options.keys, contains('json'));
      expect(parser.options['json']!.defaultsTo, isFalse);
    });

    test('handle with --json prints the whole envelope', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'json': true}),
        output: output,
        response: const {
          'snapshot': '- button "Save" [ref=e1]',
          'grepLiteral': true,
          'framesForced': true,
        },
      );

      final exit = await TapirSnapCommand().handle(ctx);

      expect(exit, equals(0));
      // The text mode prints only the tree, so these two fields never reach
      // an agent unless the envelope is printed.
      expect(output.content, contains('"grepLiteral":true'));
      expect(output.content, contains('"framesForced":true'));
      expect(output.content, contains('[ref=e1]'));
    });

    test('handle without --json prints the snapshot text only', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {
          'snapshot': '- button "Save" [ref=e1]',
          'grepLiteral': true,
        },
      );

      await TapirSnapCommand().handle(ctx);

      expect(output.content, equals('- button "Save" [ref=e1]\n'));
    });

    test('handle forwards the narrowing options to ext.tapir.snap', () async {
      // The three narrowing options are what make a snapshot answerable on a
      // large screen; a command that swallows one sends back the whole tree
      // and the caller reads it as the scoped answer.
      final ctx = _StubContext(
        input: MapInput(const {
          'within': 'e3',
          'interactiveOnly': true,
          'grep': 'Counter',
        }),
        output: BufferedOutput(),
        response: const {'snapshot': ''},
      );

      await TapirSnapCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('within', 'e3'));
      expect(ctx.lastParams, containsPair('interactiveOnly', 'true'));
      expect(ctx.lastParams, containsPair('grep', 'Counter'));
    });

    test('handle omits the narrowing options when they are empty', () async {
      final ctx = _StubContext(
        input: MapInput(const {'within': '', 'grep': ''}),
        output: BufferedOutput(),
        response: const {'snapshot': ''},
      );

      await TapirSnapCommand().handle(ctx);

      expect(ctx.lastParams!.containsKey('within'), isFalse);
      expect(ctx.lastParams!.containsKey('grep'), isFalse);
      expect(ctx.lastParams!.containsKey('interactiveOnly'), isFalse);
    });
  });
}
