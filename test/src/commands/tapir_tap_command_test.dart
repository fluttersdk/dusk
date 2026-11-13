import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_tap_command.dart';

import '../cdp/fake_cdp_server.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    this._response = const {},
  }) : super.bare(input, output);

  final Map<String, dynamic> _response;
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
    return _response as T;
  }
}

void main() {
  group('TapirTapCommand on a hidden web tab', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tapir_tap_web_');
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('brings the page to front once and never repeats the tap', () async {
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
      await File('${stateDir.path}/state.json')
          .writeAsString(jsonEncode({'cdpPort': server.port, 'webPort': 5123}));
      StateFile.debugHomeOverride = tempDir.path;

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
        response: const {
          'ref': 'e7',
          'warnings': {
            'framesEnabled': false,
            'lifecycleState': 'hidden',
            'platform': 'web',
          },
        },
      );

      final exit = await TapirTapCommand().handle(ctx);

      expect(exit, equals(0));
      expect(frames, equals(<String>['Page.bringToFront']));
      expect(ctx.calls, equals(1));
      expect(output.content, contains('Tapped e7'));
      expect(output.content, contains('not repeated'));
    });
  });

  group('TapirTapCommand', () {
    test('name is tapir:tap', () {
      expect(TapirTapCommand().name, equals('tapir:tap'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirTapCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref option', () {
      final parser = ArgParser();
      TapirTapCommand().configure(parser);
      expect(parser.options.keys, contains('ref'));
    });

    test('handle forwards --ref to ext.tapir.tap', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );
      final exit = await TapirTapCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.tap'));
      expect(ctx.lastParams, containsPair('ref', 'e5'));
    });

    test('handle accepts q-shape refs (Playwright Locator path)', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'q3'}),
        output: BufferedOutput(),
      );
      await TapirTapCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('ref', 'q3'));
    });

    test('configure declares --until and --untilTimeoutMs options', () {
      final parser = ArgParser();
      TapirTapCommand().configure(parser);
      expect(
        parser.options.keys,
        containsAll(<String>['until', 'untilTimeoutMs']),
      );
    });

    test(
      'handle forwards --until and --untilTimeoutMs to ext.tapir.tap',
      () async {
        final ctx = _StubContext(
          input: MapInput(const {
            'ref': 'e5',
            'until': 'Welcome back',
            'untilTimeoutMs': '5000',
          }),
          output: BufferedOutput(),
          response: const {'ref': 'e5', 'untilMatched': true},
        );
        final exit = await TapirTapCommand().handle(ctx);
        expect(exit, equals(0));
        expect(ctx.lastParams, containsPair('until', 'Welcome back'));
        expect(ctx.lastParams, containsPair('untilTimeoutMs', '5000'));
      },
    );

    test('handle omits until params when --until is absent', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );
      await TapirTapCommand().handle(ctx);
      expect(ctx.lastParams!.containsKey('until'), isFalse);
      expect(ctx.lastParams!.containsKey('untilTimeoutMs'), isFalse);
    });

    test('handle returns 1 when --ref is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await TapirTapCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns 1 when --ref is empty', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': ''}),
        output: BufferedOutput(),
      );
      final exit = await TapirTapCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('--json prints the envelope instead of the summary', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'json': true}),
        output: output,
        response: const {
          'ref': 'e7',
          'effect': {'kind': 'treeChanged', 'changed': true},
        },
      );

      final exit = await TapirTapCommand().handle(ctx);

      expect(exit, equals(0));
      expect(output.content, contains('"kind":"treeChanged"'));
      expect(output.content, isNot(contains('Tapped e7')));
    });

    test('the summary names a tap that changed nothing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
        response: const {
          'ref': 'e7',
          'effect': {'kind': 'treeChanged', 'changed': false},
        },
      );

      await TapirTapCommand().handle(ctx);

      expect(output.content, contains('no observable change'));
    });

    test(
      'handle surfaces the frame-production banner beside the success line',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e7'}),
          output: output,
          response: const {
            'ref': 'e7',
            'warnings': {
              'framesEnabled': false,
              'lifecycleState': 'hidden',
              'hint': 'The engine is not producing frames...',
            },
          },
        );

        final exit = await TapirTapCommand().handle(ctx);

        expect(exit, equals(0));
        // The default path prints `✓ Tapped e7` and discards the envelope, so
        // a tap that could not possibly land would otherwise read as a success.
        expect(output.content, contains('Tapped e7'));
        expect(output.content, contains('not producing frames'));
      },
    );

    test('a tap point outside the control prints one warning line', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
        response: const {
          'ref': 'e7',
          'tapPointOutsideOwner': {
            'ownerRect': {
              'left': 216.0,
              'top': 80.0,
              'width': 72.0,
              'height': 28.0,
            },
            'point': {'x': 150.0, 'y': 60.0},
          },
        },
      );

      final exit = await TapirTapCommand().handle(ctx);

      expect(exit, equals(0));
      expect(output.content, contains('Tapped e7'));
      expect(output.content, contains('(150.0, 60.0)'));
      expect(output.content, contains('outside the control'));
      expect(output.content, contains('216.0, 80.0, 72.0x28.0'));
    });

    test(
      'a retargeted tap says it went to the control, not the centre',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e7'}),
          output: output,
          response: const {
            'ref': 'e7',
            'retargeted': {
              'from': {'x': 400.0, 'y': 300.0},
              'to': {'x': 716.0, 'y': 556.0},
              'ownerRect': {
                'left': 656.0,
                'top': 536.0,
                'width': 120.0,
                'height': 40.0,
              },
            },
          },
        );

        final exit = await TapirTapCommand().handle(ctx);

        expect(exit, equals(0));
        expect(output.content, contains('Tapped e7 on its control'));
        expect(output.content, contains('(716.0, 556.0)'));
        expect(output.content, contains('(400.0, 300.0)'));
        expect(output.content, isNot(contains('outside the control')));
      },
    );

    test('a retargeted tap over a handled centre names the opt-out', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
        response: const {
          'ref': 'e7',
          'retargeted': {
            'from': {'x': 400.0, 'y': 300.0},
            'to': {'x': 716.0, 'y': 556.0},
            'ownerRect': {
              'left': 656.0,
              'top': 536.0,
              'width': 120.0,
              'height': 40.0,
            },
            'centreHandled': true,
          },
        },
      );

      await TapirTapCommand().handle(ctx);

      expect(output.content, contains('--no-retarget'));
    });

    test('--no-retarget reaches the extension as retarget: false', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'retarget': false}),
        output: BufferedOutput(),
        response: const {'ref': 'e7'},
      );

      await TapirTapCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('retarget', 'false'));
    });

    test('a default tap sends no retarget param', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
        response: const {'ref': 'e7'},
      );

      await TapirTapCommand().handle(ctx);

      expect(ctx.lastParams, isNot(contains('retarget')));
    });

    test('a tap inside the control prints no warning', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: output,
        response: const {'ref': 'e7'},
      );

      await TapirTapCommand().handle(ctx);

      expect(output.content, isNot(contains('outside the control')));
    });

    group('--snapshot', () {
      test('configure offers full, diff and none', () {
        final parser = ArgParser();
        TapirTapCommand().configure(parser);
        expect(parser.options['snapshot']!.allowed, <String>[
          'full',
          'diff',
          'none',
        ]);
      });

      test('passes the mode through and drops includeSnapshot', () async {
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'snapshot': 'diff'}),
          output: BufferedOutput(),
        );

        await TapirTapCommand().handle(ctx);

        expect(ctx.lastParams, containsPair('snapshot', 'diff'));
        expect(ctx.lastParams!.containsKey('includeSnapshot'), isFalse);
      });

      test('prints the summary, then the snapshot text', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'snapshot': 'diff'}),
          output: output,
          response: const {
            'ref': 'e5',
            'snapshot':
                '- - button "Counter: 0" [ref=e5]\n'
                '+ - button "Counter: 1" [ref=e5]\n'
                '(2 of 9 lines changed)',
            'snapshotMode': 'diff',
          },
        );

        final exit = await TapirTapCommand().handle(ctx);

        expect(exit, equals(0));
        final String content = output.content;
        expect(content, isNot(contains('"snapshotMode"')));
        expect(content.indexOf('Tapped e5'), greaterThanOrEqualTo(0));
        expect(
          content.indexOf('Tapped e5'),
          lessThan(content.indexOf('- - button "Counter: 0" [ref=e5]')),
        );
        expect(content, contains('(2 of 9 lines changed)'));
      });

      test('--snapshot=none prints the summary alone', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'snapshot': 'none'}),
          output: output,
          response: const {'ref': 'e5'},
        );

        await TapirTapCommand().handle(ctx);

        expect(ctx.lastParams, containsPair('snapshot', 'none'));
        expect(output.content.trim().split('\n'), hasLength(1));
      });
    });
  });
}
