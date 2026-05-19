import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_hot_reload_and_snap_command.dart';

/// Stubs [ArtisanContext.callExtension] so tests never hit a real VM Service.
///
/// Records every `(method, params)` pair so the test can assert ordering
/// (snap before screenshot before exceptions) and per-extension routing.
class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
    Map<String, Map<String, dynamic>> responses = const {},
    Set<String> failingExtensions = const <String>{},
  })  : _responses = responses,
        _failingExtensions = failingExtensions,
        super.bare(input, output);

  final Map<String, Map<String, dynamic>> _responses;
  final Set<String> _failingExtensions;
  final List<String> methodLog = <String>[];
  final List<Map<String, dynamic>?> paramsLog = <Map<String, dynamic>?>[];

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    methodLog.add(method);
    paramsLog.add(params);
    if (_failingExtensions.contains(method)) {
      throw StateError('stub: $method failed');
    }
    return (_responses[method] ?? const <String, dynamic>{}) as T;
  }
}

/// Builds a [HotReloadFn] that returns the supplied [HotReloadResult] after
/// a small delay, so the command's `durationMs` is always strictly positive.
HotReloadFn _fakeReload(HotReloadResult result, {int delayMs = 5}) {
  return (ArtisanContext ctx) async {
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    return result;
  };
}

void main() {
  group('DuskHotReloadAndSnapCommand', () {
    test('name is dusk:hot_reload_and_snap', () {
      expect(
        DuskHotReloadAndSnapCommand().name,
        equals('dusk:hot_reload_and_snap'),
      );
    });

    test('boot is CommandBoot.connected', () {
      expect(
        DuskHotReloadAndSnapCommand().boot,
        equals(CommandBoot.connected),
      );
    });

    test('description is non-empty', () {
      expect(DuskHotReloadAndSnapCommand().description, isNotEmpty);
    });

    test('configure declares --no-screenshot flag', () {
      final parser = ArgParser();
      DuskHotReloadAndSnapCommand().configure(parser);
      expect(parser.options.keys, contains('screenshot'));
    });

    // -------------------------------------------------------------------------
    // 1. Happy path — all 5 fields populated.
    // -------------------------------------------------------------------------
    test('happy path returns reloaded=true with snapshot+screenshot+exceptions',
        () async {
      final cmd = DuskHotReloadAndSnapCommand(
        reloadFn: _fakeReload(
          const HotReloadResult(success: true),
        ),
      );
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.dusk.snap': const {
            'snapshot': 'role: app\n  label: "Home"',
            'groupId': 'snapshot-123',
          },
          'ext.dusk.screenshot': const {
            'format': 'jpeg',
            'base64': 'AAAA',
            'width': 100,
            'height': 200,
          },
          'ext.dusk.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      final code = await cmd.handle(ctx);
      expect(code, equals(0));

      final result = cmd.lastResult;
      expect(result, isNotNull);
      expect(result!['reloaded'], isTrue);
      expect(result['durationMs'], isA<int>());
      expect(result['durationMs'] as int, greaterThan(0));
      expect(result['snapshot'], equals('role: app\n  label: "Home"'));
      expect(result['screenshot'], equals('AAAA'));
      expect(result['recentExceptions'], isA<List<dynamic>>());

      // Ordering: snap → screenshot → exceptions.
      expect(
          ctx.methodLog,
          equals(<String>[
            'ext.dusk.snap',
            'ext.dusk.screenshot',
            'ext.dusk.exceptions',
          ]));
    });

    // -------------------------------------------------------------------------
    // 2. Compile-error path — skip snap+screenshot, still gather exceptions.
    // -------------------------------------------------------------------------
    test('compile-error path returns reloaded=false with error string',
        () async {
      final cmd = DuskHotReloadAndSnapCommand(
        reloadFn: _fakeReload(
          const HotReloadResult(
            success: false,
            error: "lib/main.dart:5:1: Error: expected ';'",
          ),
        ),
      );
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.dusk.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      final code = await cmd.handle(ctx);
      expect(code, equals(0));

      final result = cmd.lastResult!;
      expect(result['reloaded'], isFalse);
      expect(result['error'], contains("expected ';'"));
      expect(result['durationMs'], isA<int>());
      expect(result['durationMs'] as int, greaterThan(0));
      expect(result.containsKey('snapshot'), isFalse);
      expect(result.containsKey('screenshot'), isFalse);
      expect(result['recentExceptions'], isA<List<dynamic>>());

      // Only ext.dusk.exceptions was called on the failure path.
      expect(ctx.methodLog, equals(<String>['ext.dusk.exceptions']));
    });

    // -------------------------------------------------------------------------
    // 3. Screenshot fails but snap succeeds — partial result with
    //    screenshotError instead of bailing the whole round-trip.
    // -------------------------------------------------------------------------
    test('screenshot failure surfaces as screenshotError, other fields stay',
        () async {
      final cmd = DuskHotReloadAndSnapCommand(
        reloadFn: _fakeReload(const HotReloadResult(success: true)),
      );
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.dusk.snap': const {
            'snapshot': 'role: app',
            'groupId': 'snapshot-1',
          },
          'ext.dusk.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
        failingExtensions: const <String>{'ext.dusk.screenshot'},
      );

      final code = await cmd.handle(ctx);
      expect(code, equals(0));

      final result = cmd.lastResult!;
      expect(result['reloaded'], isTrue);
      expect(result['snapshot'], equals('role: app'));
      expect(result.containsKey('screenshot'), isFalse);
      expect(result['screenshotError'], contains('failed'));
      expect(result['recentExceptions'], isA<List<dynamic>>());
    });

    // -------------------------------------------------------------------------
    // 4. Exceptions empty by default.
    // -------------------------------------------------------------------------
    test('recentExceptions is an empty list when telescope returns none',
        () async {
      final cmd = DuskHotReloadAndSnapCommand(
        reloadFn: _fakeReload(const HotReloadResult(success: true)),
      );
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.dusk.snap': const {'snapshot': 'r', 'groupId': 'g'},
          'ext.dusk.screenshot': const {
            'format': 'jpeg',
            'base64': 'X',
            'width': 1,
            'height': 1,
          },
          'ext.dusk.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['recentExceptions'], isEmpty);
    });

    // -------------------------------------------------------------------------
    // 5. Exceptions populated — flow through to the response.
    // -------------------------------------------------------------------------
    test('recentExceptions surfaces the list returned by ext.dusk.exceptions',
        () async {
      final cmd = DuskHotReloadAndSnapCommand(
        reloadFn: _fakeReload(const HotReloadResult(success: true)),
      );
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.dusk.snap': const {'snapshot': 'r', 'groupId': 'g'},
          'ext.dusk.screenshot': const {
            'format': 'jpeg',
            'base64': 'X',
            'width': 1,
            'height': 1,
          },
          'ext.dusk.exceptions': const {
            'exceptions': <Map<String, dynamic>>[
              {
                'type': 'StateError',
                'message': 'boom',
                'stackHead': 'main.dart:1',
                'time': '2026-05-19T00:00:00Z',
              },
            ],
            'count': 1,
          },
        },
      );

      await cmd.handle(ctx);

      final exceptions = cmd.lastResult!['recentExceptions'] as List<dynamic>;
      expect(exceptions, hasLength(1));
      expect(
        (exceptions.first as Map<String, dynamic>)['type'],
        equals('StateError'),
      );
    });

    // -------------------------------------------------------------------------
    // 6. Timing — durationMs is a positive int captured around the reload.
    // -------------------------------------------------------------------------
    test('durationMs reflects time spent in reloadFn', () async {
      final cmd = DuskHotReloadAndSnapCommand(
        reloadFn: _fakeReload(
          const HotReloadResult(success: true),
          delayMs: 25,
        ),
      );
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.dusk.snap': const {'snapshot': 'r', 'groupId': 'g'},
          'ext.dusk.screenshot': const {
            'format': 'jpeg',
            'base64': 'X',
            'width': 1,
            'height': 1,
          },
          'ext.dusk.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['durationMs'] as int, greaterThanOrEqualTo(20));
    });

    // -------------------------------------------------------------------------
    // 7. --no-screenshot — screenshot stays null and ext.dusk.screenshot is
    //    NOT invoked.
    // -------------------------------------------------------------------------
    test('--no-screenshot skips screenshot capture entirely', () async {
      final cmd = DuskHotReloadAndSnapCommand(
        reloadFn: _fakeReload(const HotReloadResult(success: true)),
      );
      final ctx = _StubContext(
        input: MapInput(const {'screenshot': false}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.dusk.snap': const {'snapshot': 'r', 'groupId': 'g'},
          'ext.dusk.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['screenshot'], isNull);
      expect(ctx.methodLog, isNot(contains('ext.dusk.screenshot')));
    });
  });
}
