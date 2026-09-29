import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/perf/perf_actions.dart';
import 'package:fluttersdk_dusk/src/perf/perf_redaction.dart';
import 'package:fluttersdk_dusk/src/perf/perf_run_driver.dart';
import 'package:fluttersdk_dusk/src/perf/perf_setup_runner.dart';
import 'package:fluttersdk_dusk/src/perf/scenario.dart';

/// One call the runner made, in order.
typedef _Call = ({String method, Map<String, dynamic> params});

/// A driver whose screen shows [shown] texts, some only after a number of
/// `ext.dusk.find` polls, and whose Router is always mounted.
final class _ScreenDriver implements PerfRunDriver {
  _ScreenDriver({
    Map<String, int>? appearsAfter,
    this.shown = const <String>{},
    this.navigateHonoured = true,
    this.answersUri = true,
    this.exceptions = const <Map<String, dynamic>>[],
  }) : appearsAfter = appearsAfter ?? <String, int>{};

  /// What `ext.dusk.exceptions` lists, newest first.
  final List<Map<String, dynamic>> exceptions;

  /// Texts on screen from the first poll.
  final Set<String> shown;

  /// Texts that answer no match for this many polls, then show up.
  final Map<String, int> appearsAfter;

  final bool navigateHonoured;
  final bool answersUri;

  String uri = '/';
  String? _landing;

  final List<_Call> calls = <_Call>[];

  List<_Call> callsTo(String method) =>
      calls.where((_Call c) => c.method == method).toList();

  int findsOf(String text) => calls
      .where(
        (_Call c) => c.method == 'ext.dusk.find' && c.params['text'] == text,
      )
      .length;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    calls.add((method: method, params: params));
    switch (method) {
      case 'ext.dusk.find':
        final String text = params['text']!;
        final int? left = appearsAfter[text];
        if (left != null) {
          if (left > 0) {
            appearsAfter[text] = left - 1;
            return <String, dynamic>{'ref': null, 'matched': false};
          }
          return <String, dynamic>{'ref': 'q1', 'matched': true};
        }
        final bool hit = shown.contains(text);
        return <String, dynamic>{'ref': hit ? 'q1' : null, 'matched': hit};
      case 'ext.dusk.navigate':
        if (!navigateHonoured) {
          _landing = params['route'];
          return <String, dynamic>{'navigated': false};
        }
        uri = params['route']!;
        return <String, dynamic>{'navigated': true, 'route': uri};
      case 'ext.dusk.get_routes':
        if (_landing != null) {
          uri = _landing!;
          _landing = null;
          return <String, dynamic>{'uri': null};
        }
        return <String, dynamic>{if (answersUri) 'uri': uri};
      case 'ext.dusk.exceptions':
        return <String, dynamic>{'exceptions': exceptions};
      default:
        return <String, dynamic>{'ok': true};
    }
  }

  @override
  Future<Map<String, dynamic>> cdp(
    String method, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    calls.add((method: 'cdp:$method', params: params));
    return <String, dynamic>{};
  }

  @override
  Future<void> restart() async {
    calls.add((method: 'restart', params: const <String, dynamic>{}));
  }

  @override
  Future<void> pause(Duration duration) async {
    calls.add((
      method: 'pause',
      params: <String, dynamic>{'ms': duration.inMilliseconds},
    ));
  }

  @override
  Future<void> close() async {}
}

PerfSetupRunner _runner(
  _ScreenDriver driver, {
  PerfPlatform platform = PerfPlatform.android,
  ({int width, int height})? viewport,
  PerfRedactor? redactor,
}) =>
    PerfSetupRunner(
      PerfActions(driver, PerfRunEnvironment(platform: platform)),
      viewport: viewport,
      redactor: redactor,
    );

PerfSetupStep _tap(String text, {PerfSetupGuard? guard, String? origin}) =>
    PerfSetupStep.gesture(
      PerfStep(
        PerfStepVerb.tap,
        target: PerfTarget(kind: PerfTargetKind.text, value: text),
      ),
      origin: origin,
      guard: guard,
    );

void main() {
  group('PerfSetupRunner', () {
    group('.run() with a when guard', () {
      test('polls every 250 ms and runs the group once its text shows',
          () async {
        // The login form draws its field on the third poll, as a cold start
        // that is still booting does.
        final _ScreenDriver driver = _ScreenDriver(
          appearsAfter: <String, int>{'Email Address': 2},
        );
        final PerfSetupGuard guard = PerfSetupGuard(
          text: 'Email Address',
          origin: 'setup[0]',
        );

        await _runner(driver).run(
          <PerfSetupStep>[
            _tap('Email Address', guard: guard, origin: 'login.yaml steps[0]'),
          ],
          'login',
        );

        // Three polls for the guard, then the tap's own lookup.
        expect(driver.findsOf('Email Address'), 4);
        expect(
          driver
              .callsTo('pause')
              .map((_Call c) => c.params['ms'])
              .take(2)
              .toList(),
          <int>[250, 250],
        );
        expect(driver.callsTo('ext.dusk.tap'), hasLength(1));
      });

      test('skips the group when unless_text shows, and it wins over text',
          () async {
        final _ScreenDriver driver = _ScreenDriver(
          shown: <String>{'Sign in', 'Monitors', 'Afterwards'},
        );
        final PerfSetupGuard guard = PerfSetupGuard(
          text: 'Sign in',
          unlessText: 'Monitors',
          origin: 'setup[0]',
        );

        await _runner(driver).run(
          <PerfSetupStep>[
            _tap('Sign in', guard: guard),
            _tap('Sign in', guard: guard),
            _tap('Afterwards'),
          ],
          'login',
        );

        final List<_Call> taps = driver.callsTo('ext.dusk.tap');
        expect(taps, hasLength(1));
        expect(driver.findsOf('Monitors'), 1);
        expect(driver.findsOf('Afterwards'), 1);
      });

      test('skips the group on timeout when there is no unless_text', () async {
        final _ScreenDriver driver = _ScreenDriver();
        final PerfSetupGuard guard = PerfSetupGuard(
          text: 'Sign in',
          timeoutMs: 1000,
          origin: 'setup[0]',
        );

        final ({bool landedLate}) result = await _runner(driver).run(
          <PerfSetupStep>[_tap('Sign in', guard: guard)],
          'login',
        );

        // 0, 250, 500, 750 and 1000 ms: five polls cover the budget.
        expect(driver.findsOf('Sign in'), 5);
        expect(driver.callsTo('ext.dusk.tap'), isEmpty);
        expect(result.landedLate, isFalse);
      });

      test('fails on timeout naming both texts when unless_text is set',
          () async {
        final _ScreenDriver driver = _ScreenDriver();
        final PerfSetupGuard guard = PerfSetupGuard(
          text: 'Sign in',
          unlessText: 'Monitors',
          timeoutMs: 500,
          origin: 'setup[1]',
        );

        await expectLater(
          _runner(driver).run(
            <PerfSetupStep>[_tap('Sign in', guard: guard)],
            'login',
          ),
          throwsA(
            isA<PerfRunException>().having(
              (PerfRunException e) => e.message,
              'message',
              allOf(
                contains('login setup[1] (when)'),
                contains('"Sign in"'),
                contains('"Monitors"'),
                contains('500 ms'),
                contains('Diagnostics:'),
              ),
            ),
          ),
        );
        expect(driver.callsTo('ext.dusk.tap'), isEmpty);
      });

      test('decides an outer guard first and never polls an inner one it skips',
          () async {
        final _ScreenDriver driver = _ScreenDriver(shown: <String>{'Home'});
        final PerfSetupGuard outer = PerfSetupGuard(
          text: 'Sign in',
          unlessText: 'Home',
          origin: 'setup[0]',
        );
        final PerfSetupGuard inner = PerfSetupGuard(
          text: 'Two-factor',
          origin: 'login.yaml steps[1]',
          parent: outer,
        );

        await _runner(driver).run(
          <PerfSetupStep>[
            _tap('Sign in', guard: outer),
            _tap('Code', guard: inner),
          ],
          'login',
        );

        expect(driver.findsOf('Two-factor'), 0);
        expect(driver.callsTo('ext.dusk.tap'), isEmpty);
      });

      test('an inner guard that skips leaves the rest of the outer group',
          () async {
        final _ScreenDriver driver = _ScreenDriver(
          shown: <String>{'Sign in', 'Skip me'},
        );
        final PerfSetupGuard outer = PerfSetupGuard(
          text: 'Sign in',
          origin: 'setup[0]',
        );
        final PerfSetupGuard inner = PerfSetupGuard(
          text: 'Two-factor',
          unlessText: 'Skip me',
          origin: 'login.yaml steps[1]',
          parent: outer,
        );

        await _runner(driver).run(
          <PerfSetupStep>[
            _tap('Sign in', guard: outer),
            _tap('Code', guard: inner),
            _tap('Sign in', guard: outer),
          ],
          'login',
        );

        expect(driver.callsTo('ext.dusk.tap'), hasLength(2));
        // Each guard is decided once per pass.
        expect(driver.findsOf('Skip me'), 1);
      });

      test('a step the platform skips does not spend the guard', () async {
        final _ScreenDriver driver = _ScreenDriver(shown: <String>{'Sign in'});
        final PerfSetupGuard guard = PerfSetupGuard(
          text: 'Sign in',
          origin: 'setup[0]',
        );

        await _runner(driver).run(
          <PerfSetupStep>[
            PerfSetupStep.gesture(
              const PerfStep(
                PerfStepVerb.wait,
                ms: 10,
                only: <PerfPlatform>{PerfPlatform.ios},
              ),
              guard: guard,
            ),
          ],
          'login',
        );

        expect(driver.findsOf('Sign in'), 0);
      });
    });

    group('.run()', () {
      test('applies the viewport first and again after every restart',
          () async {
        final _ScreenDriver driver = _ScreenDriver();

        await _runner(
          driver,
          platform: PerfPlatform.chrome,
          viewport: (width: 390, height: 844),
        ).run(
          const <PerfSetupStep>[PerfSetupStep(PerfSetupVerb.hotRestart)],
          'list',
        );

        expect(
          driver.calls.map((_Call c) => c.method).toList(),
          <String>[
            'cdp:Emulation.setDeviceMetricsOverride',
            'restart',
            'cdp:Emulation.setDeviceMetricsOverride',
          ],
        );
        expect(driver.calls.first.params['width'], 390);
      });

      test('answers landedLate when a navigate lands after answering false',
          () async {
        final _ScreenDriver driver = _ScreenDriver(navigateHonoured: false);

        final ({bool landedLate}) result = await _runner(driver).run(
          const <PerfSetupStep>[
            PerfSetupStep(
              PerfSetupVerb.navigate,
              argument: '/monitors',
              origin: 'setup[0]',
            ),
          ],
          'list',
        );

        expect(result.landedLate, isTrue);
      });

      test('names a hand-built step by its index when it has no origin',
          () async {
        final _ScreenDriver driver = _ScreenDriver();

        await expectLater(
          _runner(driver).run(
            const <PerfSetupStep>[
              PerfSetupStep(
                PerfSetupVerb.waitForText,
                argument: 'Never',
                timeoutMs: 10,
              ),
            ],
            'list',
          ),
          throwsA(
            isA<PerfRunException>().having(
              (PerfRunException e) => e.message,
              'message',
              contains('list setup[0] (wait_for_text)'),
            ),
          ),
        );
      });
    });

    group('.diagnose()', () {
      test(
          'masks a secret before cutting a long exception message, so no '
          'prefix of it survives the cut', () async {
        const String secret = r'ab"c$d';
        final String head = 'x' * 197;
        final _ScreenDriver driver = _ScreenDriver(
          exceptions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'StateError',
              'message': '$head$secret was refused',
            },
          ],
        );

        final String line = await _runner(
          driver,
          redactor: PerfRedactor(<String>{secret}),
        ).diagnose();

        expect(line, contains('StateError: $head***...'));
        expect(line, isNot(contains('${head}ab')));
      });

      test('cuts a long message at 200 characters without a redactor',
          () async {
        final _ScreenDriver driver = _ScreenDriver(
          exceptions: <Map<String, dynamic>>[
            <String, dynamic>{'type': 'StateError', 'message': 'y' * 250},
          ],
        );

        final String line = await _runner(driver).diagnose();

        expect(line, contains('StateError: ${'y' * 200}...'));
        expect(line, isNot(contains('y' * 201)));
      });
    });

    group('.awaitRouter()', () {
      test('returns once get_routes names a mounted Router', () async {
        final _ScreenDriver driver = _ScreenDriver();

        await _runner(driver).awaitRouter('after_start');

        expect(driver.callsTo('ext.dusk.get_routes'), hasLength(1));
      });

      test('tells an app with an older dusk to relaunch', () async {
        final _ScreenDriver driver = _ScreenDriver(answersUri: false);

        await expectLater(
          _runner(driver).awaitRouter('after_start'),
          throwsA(
            isA<PerfRunException>().having(
              (PerfRunException e) => e.message,
              'message',
              allOf(contains('after_start'), contains('older')),
            ),
          ),
        );
      });
    });
  });
}
