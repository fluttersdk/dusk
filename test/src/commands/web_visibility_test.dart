import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/web_visibility.dart';

import '../cdp/fake_cdp_server.dart';

/// Answers each `callExtension` with the next response in [responses] and
/// records every call, so a test can tell a re-call from a single call. An
/// [Exception] in the list is thrown instead of returned, the way a DWDS
/// timeout on a hidden tab reaches the command.
class _SequenceContext extends DowelContext {
  _SequenceContext({
    required DowelOutput output,
    required List<Object> responses,
  })  : _responses = responses,
        super.bare(MapInput(const {}), output);

  final List<Object> _responses;
  final List<String> methods = <String>[];

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    methods.add(method);
    final int index =
        methods.length <= _responses.length ? methods.length - 1 : 0;
    final Object answer = _responses[index];
    if (answer is Exception) throw answer;
    return answer as T;
  }
}

/// What the app's tab reports for `document.visibilityState`.
Map<String, dynamic> _visibility(String state) => <String, dynamic>{
      'result': <String, dynamic>{'type': 'string', 'value': state},
    };

const Map<String, dynamic> _hiddenWeb = <String, dynamic>{
  'snapshot': '- stale',
  'warnings': <String, dynamic>{
    'framesEnabled': false,
    'lifecycleState': 'hidden',
    'platform': 'web',
  },
};

const Map<String, dynamic> _hiddenNative = <String, dynamic>{
  'snapshot': '- stale',
  'warnings': <String, dynamic>{
    'framesEnabled': false,
    'lifecycleState': 'hidden',
  },
};

const Map<String, dynamic> _fresh = <String, dynamic>{
  'snapshot': '- fresh',
};

void main() {
  group('callExtensionVisible()', () {
    late Directory tempDir;
    late List<String> cdpCalls;
    late FakeCdpServer server;
    String tabState = 'hidden';

    Future<void> writeState(Map<String, dynamic> data) async {
      final Directory stateDir = Directory('${tempDir.path}/.dowel');
      await stateDir.create(recursive: true);
      await File('${stateDir.path}/state.json').writeAsString(jsonEncode(data));
      StateFile.debugHomeOverride = tempDir.path;
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tapir_web_visibility_');
      cdpCalls = <String>[];
      tabState = 'hidden';
      server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:5123/',
        handlers: {
          'Page.bringToFront': (Map<String, dynamic> _) async {
            cdpCalls.add('Page.bringToFront');
            return <String, dynamic>{};
          },
          'Runtime.evaluate': (Map<String, dynamic> _) async {
            cdpCalls.add('Runtime.evaluate');
            return _visibility(tabState);
          },
        },
      );
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      await server.stop();
      await tempDir.delete(recursive: true);
    });

    test('a healthy response makes no CDP call', () async {
      await writeState({'cdpPort': server.port, 'webPort': 5123});
      final ctx = _SequenceContext(
        output: BufferedOutput(),
        responses: [_fresh],
      );

      final response = await callExtensionVisible(
        ctx,
        'ext.tapir.snap',
        const {},
        retry: true,
      );

      expect(response, same(_fresh));
      expect(ctx.methods, hasLength(1));
      expect(cdpCalls, isEmpty);
    });

    test('a non-web frame warning makes no CDP call', () async {
      await writeState({'cdpPort': server.port, 'webPort': 5123});
      final ctx = _SequenceContext(
        output: BufferedOutput(),
        responses: [_hiddenNative],
      );

      final response = await callExtensionVisible(
        ctx,
        'ext.tapir.snap',
        const {},
        retry: true,
      );

      expect(response, same(_hiddenNative));
      expect(ctx.methods, hasLength(1));
      expect(cdpCalls, isEmpty);
    });

    test('a web warning without a cdpPort makes no CDP call', () async {
      await writeState({'webPort': 5123});
      final ctx = _SequenceContext(
        output: BufferedOutput(),
        responses: [_hiddenWeb],
      );

      final response = await callExtensionVisible(
        ctx,
        'ext.tapir.snap',
        const {},
        retry: true,
      );

      expect(response, same(_hiddenWeb));
      expect(ctx.methods, hasLength(1));
      expect(cdpCalls, isEmpty);
    });

    test('a read-only verb is brought to front once and re-called once',
        () async {
      await writeState({'cdpPort': server.port, 'webPort': 5123});
      final ctx = _SequenceContext(
        output: BufferedOutput(),
        responses: [_hiddenWeb, _fresh],
      );

      final response = await callExtensionVisible(
        ctx,
        'ext.tapir.snap',
        const {},
        retry: true,
      );

      expect(cdpCalls, equals(<String>['Page.bringToFront']));
      expect(ctx.methods, equals(<String>['ext.tapir.snap', 'ext.tapir.snap']));
      expect(response, same(_fresh));
    });

    test('a mutating verb is brought to front but never re-called', () async {
      await writeState({'cdpPort': server.port, 'webPort': 5123});
      final output = BufferedOutput();
      final ctx = _SequenceContext(
        output: output,
        responses: [_hiddenWeb, _fresh],
      );

      final response = await callExtensionVisible(
        ctx,
        'ext.tapir.tap',
        const {'ref': 'e1'},
      );

      expect(cdpCalls, equals(<String>['Page.bringToFront']));
      expect(ctx.methods, equals(<String>['ext.tapir.tap']));
      expect(response, same(_hiddenWeb));
      expect(output.content, contains('not repeated'));
      expect(output.content, contains('tapir:snap'));
    });

    test('a CDP failure keeps the original response and says why', () async {
      await writeState({'cdpPort': server.port, 'webPort': 9999});
      final output = BufferedOutput();
      final ctx = _SequenceContext(
        output: output,
        responses: [_hiddenWeb, _fresh],
      );

      final response = await callExtensionVisible(
        ctx,
        'ext.tapir.snap',
        const {},
        retry: true,
      );

      expect(cdpCalls, isEmpty);
      expect(ctx.methods, hasLength(1));
      expect(response, same(_hiddenWeb));
      expect(output.content, contains('Could not bring the page to front'));
    });

    group('when the call throws (a hidden tab never answers)', () {
      final Exception timeout =
          Exception('DWDS: callServiceExtension timed out');

      test('a read-only verb on a hidden tab is brought to front and re-called',
          () async {
        await writeState({'cdpPort': server.port, 'webPort': 5123});
        final ctx = _SequenceContext(
          output: BufferedOutput(),
          responses: [timeout, _fresh],
        );

        final response = await callExtensionVisible(
          ctx,
          'ext.tapir.snap',
          const {},
          retry: true,
        );

        expect(cdpCalls,
            equals(<String>['Runtime.evaluate', 'Page.bringToFront']));
        expect(
            ctx.methods, equals(<String>['ext.tapir.snap', 'ext.tapir.snap']));
        expect(response, same(_fresh));
      });

      test(
          'a mutating verb on a hidden tab is brought to front, not re-called, '
          'and still fails', () async {
        await writeState({'cdpPort': server.port, 'webPort': 5123});
        final output = BufferedOutput();
        final ctx =
            _SequenceContext(output: output, responses: [timeout, _fresh]);

        await expectLater(
          callExtensionVisible(ctx, 'ext.tapir.tap', const {'ref': 'e1'}),
          throwsA(same(timeout)),
        );

        expect(cdpCalls,
            equals(<String>['Runtime.evaluate', 'Page.bringToFront']));
        expect(ctx.methods, equals(<String>['ext.tapir.tap']));
        expect(output.content, contains('was hidden'));
        expect(output.content, contains('tapir:snap'));
      });

      test('a tapir refusal is not a hidden-tab symptom: no CDP call, no retry',
          () async {
        await writeState({'cdpPort': server.port, 'webPort': 5123});
        final Exception refusal = Exception(
          'ext.tapir.fill: (-32000) Server error {"message":"ref e5 is a '
          'button, not a text field"}',
        );
        final ctx = _SequenceContext(
          output: BufferedOutput(),
          responses: [refusal, _fresh],
        );

        await expectLater(
          callExtensionVisible(ctx, 'ext.tapir.snap', const {}, retry: true),
          throwsA(same(refusal)),
        );

        expect(cdpCalls, isEmpty);
        expect(ctx.methods, hasLength(1));
      });

      test('a visible tab is left alone and the error propagates', () async {
        tabState = 'visible';
        await writeState({'cdpPort': server.port, 'webPort': 5123});
        final ctx = _SequenceContext(
          output: BufferedOutput(),
          responses: [timeout, _fresh],
        );

        await expectLater(
          callExtensionVisible(ctx, 'ext.tapir.snap', const {}, retry: true),
          throwsA(same(timeout)),
        );

        expect(cdpCalls, equals(<String>['Runtime.evaluate']));
        expect(ctx.methods, hasLength(1));
      });

      test('without a cdpPort the error propagates and CDP is not touched',
          () async {
        await writeState({'webPort': 5123});
        final ctx = _SequenceContext(
          output: BufferedOutput(),
          responses: [timeout, _fresh],
        );

        await expectLater(
          callExtensionVisible(ctx, 'ext.tapir.snap', const {}, retry: true),
          throwsA(same(timeout)),
        );

        expect(cdpCalls, isEmpty);
      });

      test('an unreachable CDP port leaves the original error untouched',
          () async {
        await writeState({'cdpPort': 1, 'webPort': 5123});
        final ctx = _SequenceContext(
          output: BufferedOutput(),
          responses: [timeout, _fresh],
        );

        await expectLater(
          callExtensionVisible(ctx, 'ext.tapir.snap', const {}, retry: true),
          throwsA(same(timeout)),
        );

        expect(ctx.methods, hasLength(1));
      });
    });
  });
}
