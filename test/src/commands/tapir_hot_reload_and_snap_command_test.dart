import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_hot_reload_and_snap_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
///
/// Records every `(method, params)` pair so the test can assert ordering
/// (snap before screenshot before exceptions) and per-extension routing.
class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    this._responses = const {},
    this._failingExtensions = const <String>{},
  }) : super.bare(input, output);

  final Map<String, Map<String, dynamic>> _responses;
  final Set<String> _failingExtensions;
  final List<String> methodLog = <String>[];
  final List<Map<String, dynamic>?> paramsLog = <Map<String, dynamic>?>[];

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
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
  return (DowelContext ctx) async {
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    return result;
  };
}

void main() {
  group('TapirHotReloadAndSnapCommand', () {
    test('name is tapir:hot_reload_and_snap', () {
      expect(
        TapirHotReloadAndSnapCommand().name,
        equals('tapir:hot_reload_and_snap'),
      );
    });

    test('boot is CommandBoot.connected', () {
      expect(
        TapirHotReloadAndSnapCommand().boot,
        equals(CommandBoot.connected),
      );
    });

    test('description is non-empty', () {
      expect(TapirHotReloadAndSnapCommand().description, isNotEmpty);
    });

    test('configure declares --no-screenshot flag', () {
      final parser = ArgParser();
      TapirHotReloadAndSnapCommand().configure(parser);
      expect(parser.options.keys, contains('screenshot'));
    });

    // -------------------------------------------------------------------------
    // 1. Happy path — all 5 fields populated.
    // -------------------------------------------------------------------------
    test(
      'happy path returns reloaded=true with snapshot+screenshot+exceptions',
      () async {
        final cmd = TapirHotReloadAndSnapCommand(
          reloadFn: _fakeReload(const HotReloadResult(success: true)),
        );
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: BufferedOutput(),
          responses: <String, Map<String, dynamic>>{
            'ext.tapir.snap': const {
              'snapshot': 'role: app\n  label: "Home"',
              'groupId': 'snapshot-123',
            },
            'ext.tapir.screenshot': const {
              'format': 'jpeg',
              'base64': 'AAAA',
              'width': 100,
              'height': 200,
            },
            'ext.tapir.exceptions': const {
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
            'ext.tapir.snap',
            'ext.tapir.screenshot',
            'ext.tapir.exceptions',
          ]),
        );
      },
    );

    // -------------------------------------------------------------------------
    // 2. Compile-error path — skip snap+screenshot, still gather exceptions.
    // -------------------------------------------------------------------------
    test(
      'compile-error path returns reloaded=false with error string',
      () async {
        final cmd = TapirHotReloadAndSnapCommand(
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
            'ext.tapir.exceptions': const {
              'exceptions': <Map<String, dynamic>>[],
              'count': 0,
            },
          },
        );

        final code = await cmd.handle(ctx);
        expect(code, equals(1));

        final result = cmd.lastResult!;
        expect(result['reloaded'], isFalse);
        expect(result['error'], contains("expected ';'"));
        expect(result['durationMs'], isA<int>());
        expect(result['durationMs'] as int, greaterThan(0));
        expect(result.containsKey('snapshot'), isFalse);
        expect(result.containsKey('screenshot'), isFalse);
        expect(result['recentExceptions'], isA<List<dynamic>>());

        // Only ext.tapir.exceptions was called on the failure path.
        expect(ctx.methodLog, equals(<String>['ext.tapir.exceptions']));
      },
    );

    // -------------------------------------------------------------------------
    // 3. Screenshot fails but snap succeeds — partial result with
    //    screenshotError instead of bailing the whole round-trip.
    // -------------------------------------------------------------------------
    test(
      'screenshot failure surfaces as screenshotError, other fields stay',
      () async {
        final cmd = TapirHotReloadAndSnapCommand(
          reloadFn: _fakeReload(const HotReloadResult(success: true)),
        );
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: BufferedOutput(),
          responses: <String, Map<String, dynamic>>{
            'ext.tapir.snap': const {
              'snapshot': 'role: app',
              'groupId': 'snapshot-1',
            },
            'ext.tapir.exceptions': const {
              'exceptions': <Map<String, dynamic>>[],
              'count': 0,
            },
          },
          failingExtensions: const <String>{'ext.tapir.screenshot'},
        );

        final code = await cmd.handle(ctx);
        expect(code, equals(0));

        final result = cmd.lastResult!;
        expect(result['reloaded'], isTrue);
        expect(result['snapshot'], equals('role: app'));
        expect(result.containsKey('screenshot'), isFalse);
        expect(result['screenshotError'], contains('failed'));
        expect(result['recentExceptions'], isA<List<dynamic>>());
      },
    );

    // -------------------------------------------------------------------------
    // 4. Exceptions empty by default.
    // -------------------------------------------------------------------------
    test(
      'recentExceptions is an empty list when crumbs returns none',
      () async {
        final cmd = TapirHotReloadAndSnapCommand(
          reloadFn: _fakeReload(const HotReloadResult(success: true)),
        );
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: BufferedOutput(),
          responses: <String, Map<String, dynamic>>{
            'ext.tapir.snap': const {'snapshot': 'r', 'groupId': 'g'},
            'ext.tapir.screenshot': const {
              'format': 'jpeg',
              'base64': 'X',
              'width': 1,
              'height': 1,
            },
            'ext.tapir.exceptions': const {
              'exceptions': <Map<String, dynamic>>[],
              'count': 0,
            },
          },
        );

        await cmd.handle(ctx);

        expect(cmd.lastResult!['recentExceptions'], isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // 5. Exceptions populated — flow through to the response.
    // -------------------------------------------------------------------------
    test(
      'recentExceptions surfaces the list returned by ext.tapir.exceptions',
      () async {
        final cmd = TapirHotReloadAndSnapCommand(
          reloadFn: _fakeReload(const HotReloadResult(success: true)),
        );
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: BufferedOutput(),
          responses: <String, Map<String, dynamic>>{
            'ext.tapir.snap': const {'snapshot': 'r', 'groupId': 'g'},
            'ext.tapir.screenshot': const {
              'format': 'jpeg',
              'base64': 'X',
              'width': 1,
              'height': 1,
            },
            'ext.tapir.exceptions': const {
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
      },
    );

    // -------------------------------------------------------------------------
    // 6. Timing — durationMs is a positive int captured around the reload.
    // -------------------------------------------------------------------------
    test('durationMs reflects time spent in reloadFn', () async {
      final cmd = TapirHotReloadAndSnapCommand(
        reloadFn: _fakeReload(
          const HotReloadResult(success: true),
          delayMs: 25,
        ),
      );
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.tapir.snap': const {'snapshot': 'r', 'groupId': 'g'},
          'ext.tapir.screenshot': const {
            'format': 'jpeg',
            'base64': 'X',
            'width': 1,
            'height': 1,
          },
          'ext.tapir.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['durationMs'] as int, greaterThanOrEqualTo(20));
    });

    // -------------------------------------------------------------------------
    // 7. --no-screenshot — screenshot stays null and ext.tapir.screenshot is
    //    NOT invoked.
    // -------------------------------------------------------------------------
    test('--no-screenshot skips screenshot capture entirely', () async {
      final cmd = TapirHotReloadAndSnapCommand(
        reloadFn: _fakeReload(const HotReloadResult(success: true)),
      );
      final ctx = _StubContext(
        input: MapInput(const {'screenshot': false}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.tapir.snap': const {'snapshot': 'r', 'groupId': 'g'},
          'ext.tapir.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['screenshot'], isNull);
      expect(ctx.methodLog, isNot(contains('ext.tapir.screenshot')));
    });
  });

  // ===========================================================================
  // Default reload path — exercises the production `_defaultReload`
  // (FIFO stdin + log poll) via the no-arg ctor so the file's largest
  // uncovered branch becomes reachable in coverage.
  // ===========================================================================
  group('TapirHotReloadAndSnapCommand defaultReload integration', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync(
        'tapir_hot_reload_default_',
      );
      StateFile.debugHomeOverride = tempHome.path;
      Directory('${tempHome.path}/.dowel').createSync(recursive: true);
    });

    tearDown(() {
      StateFile.debugHomeOverride = null;
      if (tempHome.existsSync()) {
        tempHome.deleteSync(recursive: true);
      }
    });

    test('reloaded=false when state.json is absent', () async {
      // No state.json written → StateFile.read() returns null.
      final cmd = TapirHotReloadAndSnapCommand(); // default _defaultReload
      final ctx = _StubContext(
        input: MapInput(const {'screenshot': false}),
        output: BufferedOutput(),
      );
      await cmd.handle(ctx);
      expect(cmd.lastResult!['reloaded'], isFalse);
      expect(
        cmd.lastResult!['error'] as String,
        contains('No dowel state file'),
      );
    });

    test('reloaded=false when state.json has no stdinPipe entry', () async {
      File('${tempHome.path}/.dowel/state.json')
          .writeAsStringSync(jsonEncode({'pid': 1, 'vmServiceUri': 'ws://x'}));
      final cmd = TapirHotReloadAndSnapCommand();
      final ctx = _StubContext(
        input: MapInput(const {'screenshot': false}),
        output: BufferedOutput(),
      );
      await cmd.handle(ctx);
      expect(cmd.lastResult!['reloaded'], isFalse);
      expect(
        cmd.lastResult!['error'] as String,
        contains('no stdinPipe entry'),
      );
    });

    test(
      'reloaded=false when the recorded stdin pipe is missing on disk',
      () async {
        File('${tempHome.path}/.dowel/state.json').writeAsStringSync(
          jsonEncode({
            'pid': 1,
            'stdinPipe': '${tempHome.path}/.dowel/nonexistent.fifo',
          }),
        );
        final cmd = TapirHotReloadAndSnapCommand();
        final ctx = _StubContext(
          input: MapInput(const {'screenshot': false}),
          output: BufferedOutput(),
        );
        await cmd.handle(ctx);
        expect(cmd.lastResult!['reloaded'], isFalse);
        expect(
          cmd.lastResult!['error'] as String,
          contains('flutter run stdin pipe missing'),
        );
      },
    );

    test('reloaded=true when the success marker appears in the log after '
        'the keystroke write', () async {
      final pipeFile = File('${tempHome.path}/.dowel/pipe')..createSync();
      final logFile = File('${tempHome.path}/.dowel/flutter-dev.log')
        ..writeAsStringSync('Launching app...\n');
      File('${tempHome.path}/.dowel/state.json').writeAsStringSync(
        jsonEncode({
          'pid': 1,
          'stdinPipe': pipeFile.path,
          'logPath': logFile.path,
        }),
      );

      // Append the success marker shortly after handle() starts polling.
      // 120ms gives the printf write time to complete; the loop polls
      // every 50ms so the marker is seen within ~one extra cycle.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          logFile.writeAsStringSync(
            'Reloaded 0 of 1 libraries in 50ms (compile: 5 ms, reload: 0 ms).\n',
            mode: FileMode.append,
          );
        }),
      );

      final cmd = TapirHotReloadAndSnapCommand();
      final ctx = _StubContext(
        input: MapInput(const {'screenshot': false}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.tapir.snap': const {'snapshot': '- root', 'groupId': 'g'},
          'ext.tapir.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['reloaded'], isTrue);
      expect(cmd.lastResult!['snapshot'], equals('- root'));
      expect(pipeFile.readAsStringSync(), equals('r\n'));
    });

    test('reads the per-session log next to the state file when state.json has '
        'no logPath', () async {
      final sessionDir = Directory('${tempHome.path}/.dowel/sessions/abc123')
        ..createSync(recursive: true);
      final pipeFile = File('${sessionDir.path}/flutter-dev.fifo')
        ..createSync();
      final logFile = File('${sessionDir.path}/flutter-dev.log')
        ..writeAsStringSync('Launching app...\n');
      File(
        '${sessionDir.path}/state.json',
      ).writeAsStringSync(jsonEncode({'pid': 1, 'stdinPipe': pipeFile.path}));
      StateFile.pathOverride = '${sessionDir.path}/state.json';
      addTearDown(() => StateFile.pathOverride = null);

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          logFile.writeAsStringSync(
            'Reloaded 0 of 1 libraries in 50ms (compile: 5 ms, reload: 0 ms).\n',
            mode: FileMode.append,
          );
        }),
      );

      final cmd = TapirHotReloadAndSnapCommand();
      final ctx = _StubContext(
        input: MapInput(const {'screenshot': false}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.tapir.snap': const {'snapshot': '- root', 'groupId': 'g'},
          'ext.tapir.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['reloaded'], isTrue);
    });

    test('reloaded=false with compile-error envelope when the failure marker '
        'appears in the log', () async {
      final pipeFile = File('${tempHome.path}/.dowel/pipe')..createSync();
      final logFile = File('${tempHome.path}/.dowel/flutter-dev.log')
        ..writeAsStringSync('Launching app...\n');
      File('${tempHome.path}/.dowel/state.json').writeAsStringSync(
        jsonEncode({
          'pid': 1,
          'stdinPipe': pipeFile.path,
          'logPath': logFile.path,
        }),
      );

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          logFile.writeAsStringSync(
            "lib/main.dart:5:1: Error: expected ';'\n"
            'Try again after fixing the above error(s).\n',
            mode: FileMode.append,
          );
        }),
      );

      final cmd = TapirHotReloadAndSnapCommand();
      final ctx = _StubContext(
        input: MapInput(const {'screenshot': false}),
        output: BufferedOutput(),
        responses: <String, Map<String, dynamic>>{
          'ext.tapir.exceptions': const {
            'exceptions': <Map<String, dynamic>>[],
            'count': 0,
          },
        },
      );

      await cmd.handle(ctx);

      expect(cmd.lastResult!['reloaded'], isFalse);
      expect(cmd.lastResult!['error'] as String, contains('compile error'));
    });
  });
}
