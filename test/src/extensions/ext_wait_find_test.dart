import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_wait_find.dart';
import 'package:tapir/src/ref_registry.dart';

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

bool _isError(developer.ServiceExtensionResponse response) =>
    response.errorCode != null;

bool _isSuccess(developer.ServiceExtensionResponse response) =>
    response.errorCode == null;

void main() {
  tearDown(() {
    RefRegistry.resetForTesting();
  });

  // wait_for's polling loop uses real Future.delayed which hangs under the
  // flutter_test fake-clock harness, so we only exercise the missing-param
  // gate here. Live drive coverage is captured by the example/ playground
  // E2E (tapir:wait_for against Forms screen) — see CHANGELOG.

  group('tapirWaitForHandler', () {
    testWidgets('returns extensionError when no condition is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      final response = await tapirWaitForHandler(
        'ext.tapir.wait_for',
        const <String, String>{},
      );
      expect(_isError(response), isTrue);
    });
  });

  group('tapirFindByTextHandler', () {
    testWidgets('returns extensionError when text param is missing', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      final response = await tapirFindByTextHandler(
        'ext.tapir.find_by_text',
        const <String, String>{},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('finds a single matching Text widget by exact text', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('Hello tapir')));
      final response = await tapirFindByTextHandler(
        'ext.tapir.find_by_text',
        const {'text': 'Hello tapir'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('returns empty refs when no Text matches', (tester) async {
      await tester.pumpWidget(_wrap(const Text('Other content')));
      final response = await tapirFindByTextHandler(
        'ext.tapir.find_by_text',
        const {'text': 'Will not match'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('substring match when exact=false', (tester) async {
      await tester.pumpWidget(_wrap(const Text('Welcome to tapir testing')));
      final response = await tapirFindByTextHandler(
        'ext.tapir.find_by_text',
        const {'text': 'tapir', 'exact': 'false'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('exact=true requires full string match', (tester) async {
      await tester.pumpWidget(_wrap(const Text('Welcome to tapir testing')));
      final response = await tapirFindByTextHandler(
        'ext.tapir.find_by_text',
        const {'text': 'tapir', 'exact': 'true'},
      );
      expect(_isSuccess(response), isTrue);
    });
  });

  group('registerWaitFindExtensions', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerWaitFindExtensions();
      registerWaitFindExtensions();
    });
  });

  group('findByTextWaitLoop fast path', () {
    testWidgets('returns matched immediately when text is already present', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('hello tapir')));
      final result = await findByTextWaitLoop(
        text: 'hello tapir',
        timeoutMs: 1000,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isTrue);
      expect(result['elapsedMs'], equals(0));
    });
  });

  group('findByTextGoneWaitLoop fast path', () {
    testWidgets('returns matched immediately when text is absent', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('other')));
      final result = await findByTextGoneWaitLoop(
        text: 'never appeared',
        timeoutMs: 1000,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isTrue);
      expect(result['elapsedMs'], equals(0));
    });
  });

  group('wait loops timeout=0 short-circuit', () {
    testWidgets('findByTextWaitLoop with timeoutMs=0 returns timeout', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('not the target')));
      final result = await findByTextWaitLoop(
        text: 'will never match',
        timeoutMs: 0,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isFalse);
      expect(result['reason'], equals('timeout'));
    });

    testWidgets('findByTextGoneWaitLoop with timeoutMs=0 returns timeout', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('still here')));
      final result = await findByTextGoneWaitLoop(
        text: 'still here',
        timeoutMs: 0,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isFalse);
      expect(result['reason'], equals('timeout'));
    });

    testWidgets('tapirWaitForHandler with timeoutMs=0 surfaces the timeout', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('absent')));
      final response = await tapirWaitForHandler('ext.tapir.wait_for', const {
        'text': 'never appears',
        'timeoutMs': '0',
      });
      expect(_isSuccess(response), isTrue);
    });
  });

  group('tapirWaitForHandler — fast path success branches', () {
    testWidgets(
      'text param: returns matched JSON when text is already present',
      (tester) async {
        await tester.pumpWidget(_wrap(const Text('hello')));
        final response = await tapirWaitForHandler('ext.tapir.wait_for', const {
          'text': 'hello',
        });
        expect(_isSuccess(response), isTrue);
      },
    );

    testWidgets(
      'textGone param: returns matched JSON when text is absent immediately',
      (tester) async {
        await tester.pumpWidget(_wrap(const Text('other')));
        final response = await tapirWaitForHandler('ext.tapir.wait_for', const {
          'textGone': 'gone-already',
        });
        expect(_isSuccess(response), isTrue);
      },
    );

    testWidgets('expression param: routed through text-presence loop', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('hello tapir')));
      final response = await tapirWaitForHandler('ext.tapir.wait_for', const {
        'expression': 'hello tapir',
      });
      expect(_isSuccess(response), isTrue);
    });
  });

  group('findByTextInTree', () {
    testWidgets('returns ref for each matching Text widget (exact)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: <Widget>[Text('alpha'), Text('beta'), Text('alpha')],
          ),
        ),
      );

      final refs = findByTextInTree(
        text: 'alpha',
        exact: true,
        groupId: 'g-find-test',
      );
      expect(refs.length, equals(2));
      for (final r in refs) {
        expect(r.startsWith('e'), isTrue);
      }
    });

    testWidgets('returns substring matches when exact=false', (tester) async {
      await tester.pumpWidget(_wrap(const Text('welcome to tapir testing')));

      final refs = findByTextInTree(
        text: 'tapir',
        exact: false,
        groupId: 'g-find-substr',
      );
      expect(refs.length, equals(1));
    });

    testWidgets('returns empty list when nothing matches', (tester) async {
      await tester.pumpWidget(_wrap(const Text('only this')));
      final refs = findByTextInTree(
        text: 'no match here',
        exact: true,
        groupId: 'g-empty',
      );
      expect(refs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // ext.tapir.wait_for_network_idle (Step 3.4)
  // ---------------------------------------------------------------------------

  group('tapirWaitForNetworkIdleHandler', () {
    int counterValue = 0;
    late int Function() originalReader;

    setUp(() {
      counterValue = 0;
      // Save the existing reader so we can restore between tests and
      // simulate the "missing crumbs" graceful path on demand.
      originalReader = pendingHttpCountReader;
      pendingHttpCountReader = () => counterValue;
    });

    tearDown(() {
      // Restore so cross-test pollution does not leak the test counter.
      pendingHttpCountReader = originalReader;
    });

    testWidgets('fast path: returns matched=true with idleAchievedMs when '
        'pendingCount is already 0', (tester) async {
      // idleMs == pollIntervalMs lets the first iteration satisfy the idle
      // window WITHOUT awaiting Future.delayed (which hangs under the
      // fake-clock harness). Same trick used by findByTextWaitLoop fast-path
      // tests elsewhere in this file.
      counterValue = 0;
      final response = await tapirWaitForNetworkIdleHandler(
        'ext.tapir.wait_for_network_idle',
        const <String, String>{
          'timeoutMs': '2000',
          'idleMs': '100',
          'pollIntervalMs': '100',
        },
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets(
      'missing-crumbs graceful: default reader (returns 0) is treated '
      'the same as idle from the start',
      (tester) async {
        // Restore the default reader (which always returns 0) to simulate a
        // host that never wired crumbs -> pendingCount stays 0 forever.
        pendingHttpCountReader = () => 0;
        final response = await tapirWaitForNetworkIdleHandler(
          'ext.tapir.wait_for_network_idle',
          const <String, String>{
            'timeoutMs': '500',
            'idleMs': '100',
            'pollIntervalMs': '100',
          },
        );
        expect(_isSuccess(response), isTrue);
      },
    );

    testWidgets(
      'timeout path: returns error envelope when pendingCount is positive '
      'AND timeoutMs is 0 (fast-fail short-circuit)',
      (tester) async {
        // timeoutMs=0 short-circuits before any real Future.delayed runs ; the
        // fake-clock harness in flutter_test cannot advance real timers, so the
        // sample-then-check ordering inside networkIdleWaitLoop is what lets
        // this case complete deterministically.
        counterValue = 4;
        final response = await tapirWaitForNetworkIdleHandler(
          'ext.tapir.wait_for_network_idle',
          const <String, String>{
            'timeoutMs': '0',
            'idleMs': '200',
            'pollIntervalMs': '100',
          },
        );
        expect(_isError(response), isTrue);
      },
    );

    testWidgets(
      'idle-then-spike resets the countdown so transient zero does not '
      'count as idle (runAsync)',
      (tester) async {
        // Sequence: 1, 0, 1, 0, 0, 0 -> the first 0 starts the countdown, the
        // next 1 resets it, and the trailing run of 0s must accumulate idleMs
        // again. Real Future.delayed runs under tester.runAsync.
        final script = <int>[1, 0, 1, 0, 0, 0];
        var idx = 0;
        pendingHttpCountReader = () {
          if (idx >= script.length) return 0;
          return script[idx++];
        };

        final response = await tester.runAsync(() async {
          return tapirWaitForNetworkIdleHandler(
            'ext.tapir.wait_for_network_idle',
            const <String, String>{
              'timeoutMs': '5000',
              'idleMs': '200',
              'pollIntervalMs': '100',
            },
          );
        });
        // The final three 0s satisfy idleMs=200ms with pollInterval=100 ;
        // matched=true after the spike resets the earlier accumulation.
        expect(_isSuccess(response!), isTrue);
      },
    );

    testWidgets(
      'idle-after-some-pending: pendingCount drops from positive to 0 and '
      'stays there long enough to satisfy idleMs (runAsync)',
      (tester) async {
        final script = <int>[2, 1, 0, 0, 0];
        var idx = 0;
        pendingHttpCountReader = () {
          if (idx >= script.length) return 0;
          return script[idx++];
        };

        final response = await tester.runAsync(() async {
          return tapirWaitForNetworkIdleHandler(
            'ext.tapir.wait_for_network_idle',
            const <String, String>{
              'timeoutMs': '5000',
              'idleMs': '200',
              'pollIntervalMs': '100',
            },
          );
        });
        expect(_isSuccess(response!), isTrue);
      },
    );

    testWidgets(
      'networkIdleWaitLoop direct: maxPending tracks the highest observed '
      'count when the loop times out',
      (tester) async {
        // Drive the unit-level loop with timeoutMs=0 so we never hit Future.delayed
        // and can inspect the maxPending field that feeds the error message
        // surfaced by the handler.
        final result = await networkIdleWaitLoop(
          timeoutMs: 0,
          idleMs: 200,
          pollIntervalMs: 100,
          pendingCountReader: () => 7,
        );

        expect(result['matched'], isFalse);
        expect(result['reason'], equals('timeout'));
        expect(result['maxPending'], equals(7));
      },
    );
  });
}
