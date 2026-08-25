import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind_diagnostics_contracts/fluttersdk_wind_diagnostics_contracts.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_perf.dart';
import 'package:fluttersdk_dusk/src/utils/perf_readers.dart';

/// Wind is not a dependency of dusk, so the wind section is read through the
/// neutral contracts package. Faking the contract is the only way to prove
/// the read happens.
final class _FakeWindPerfResolver implements WindPerfResolver {
  @override
  Map<String, Object?> stats() => <String, Object?>{
        'cacheHits': 12,
        'cacheMisses': 3,
        'cacheBypasses': 40,
        'cacheSize': 7,
        'wDivBuilds': 88,
        'wTextBuilds': 64,
      };
}

/// One frame shaped exactly like telescope's `FramePerfRecord.toJson()`.
Map<String, Object?> _frame({
  required int frameNumber,
  required int buildMicros,
  required int rasterMicros,
  Map<String, Object?> blocks = const <String, Object?>{},
}) =>
    <String, Object?>{
      'frameNumber': frameNumber,
      'buildMicros': buildMicros,
      'rasterMicros': rasterMicros,
      'vsyncOverheadMicros': 100,
      'totalSpanMicros': buildMicros + rasterMicros,
      'time': '2026-08-25T10:00:00.000Z',
      'blocks': blocks,
    };

Map<String, Object?> _block(int micros, int count) =>
    <String, Object?>{'micros': micros, 'count': count};

/// The two-frame fixture every payload-shape test reads.
final List<Map<String, Object?>> _fixtureFrames = <Map<String, Object?>>[
  _frame(
    frameNumber: 10,
    buildMicros: 4000,
    rasterMicros: 3000,
    blocks: <String, Object?>{
      'MonitorRow': _block(1200, 4),
      'WText': _block(400, 20),
    },
  ),
  _frame(
    frameNumber: 11,
    buildMicros: 20000,
    rasterMicros: 5000,
    blocks: <String, Object?>{
      'MonitorRow': _block(9000, 6),
      'WDiv': _block(300, 2),
    },
  ),
];

/// Decodes a success payload, reporting the error detail rather than
/// crashing on a null check when the handler answered with an error.
Map<String, dynamic> _decode(developer.ServiceExtensionResponse response) {
  final String? body = response.result;
  if (body == null) {
    throw StateError(
      'expected a success response, got error: ${response.errorDetail}',
    );
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    framePerfReader = () => <String, Object?>{
          'frames': <Map<String, Object?>>[],
          'livenessCounter': 0,
        };
    perfExtrasReader = () => <String, Object?>{
          'controllerNotifies': <String, int>{},
          'routeTransitions': <Map<String, Object?>>[],
        };
    perfSessionBeginHook = () {};
    perfSessionEndHook = () {};
    WindDebugRegistry.resetForTesting();
  });

  tearDown(() {
    // A leaked session would carry stale prior-flag values into the next
    // test; the reset restores them the same way perf_end does.
    resetPerfSessionForTesting();
    FlutterTimeline.debugCollectionEnabled = false;
    debugProfileBuildsEnabled = false;
    debugProfileBuildsEnabledUserWidgets = false;
    debugProfileLayoutsEnabled = false;
    debugProfilePaintsEnabled = false;
    WindDebugRegistry.resetForTesting();
  });

  group('registerPerfExtensions()', () {
    test('registers both verbs and is safe to call twice', () {
      expect(registerPerfExtensions, returnsNormally);
      expect(registerPerfExtensions, returnsNormally);
    });
  });

  group('ext.dusk.perf_begin', () {
    test('opens a session, returns a token, and defaults phases to false',
        () async {
      final Map<String, dynamic> payload = _decode(
        await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{}),
      );

      expect(payload['sessionToken'], isA<String>());
      expect((payload['sessionToken'] as String).isNotEmpty, isTrue);
      expect(payload['phases'], isFalse);
      expect(payload['restartedPreviousSession'], isFalse);
    });

    test('enables collection and the build flags, leaving the phase flags off',
        () async {
      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});

      expect(FlutterTimeline.debugCollectionEnabled, isTrue);
      expect(debugProfileBuildsEnabled, isTrue);
      expect(debugProfileBuildsEnabledUserWidgets, isTrue);
      expect(debugProfileLayoutsEnabled, isFalse);
      expect(debugProfilePaintsEnabled, isFalse);
    });

    test('phases=true also enables the layout and paint flags', () async {
      final Map<String, dynamic> payload = _decode(
        await duskPerfBeginHandler(
          'ext.dusk.perf_begin',
          <String, String>{'phases': 'true'},
        ),
      );

      expect(payload['phases'], isTrue);
      expect(debugProfileLayoutsEnabled, isTrue);
      expect(debugProfilePaintsEnabled, isTrue);
    });

    test('calls perfSessionBeginHook once and records the liveness baseline',
        () async {
      int beginCalls = 0;
      perfSessionBeginHook = () => beginCalls++;
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[],
            'livenessCounter': 41,
          };

      final Map<String, dynamic> payload = _decode(
        await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{}),
      );

      expect(beginCalls, 1);
      expect(payload['livenessBaseline'], 41);
    });

    test(
        'a second begin restores the first session flags before saving new '
        'ones, so perf_end cannot leave profiling on', () async {
      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'phases': 'true'},
      );

      final Map<String, dynamic> second = _decode(
        await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{}),
      );
      expect(second['restartedPreviousSession'], isTrue);

      framePerfReader = () => <String, Object?>{
            'frames': _fixtureFrames,
            'livenessCounter': 9,
          };
      await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});

      expect(debugProfileBuildsEnabled, isFalse);
      expect(debugProfileLayoutsEnabled, isFalse);
      expect(FlutterTimeline.debugCollectionEnabled, isFalse);
    });
  });

  group('ext.dusk.perf_end', () {
    test('without a prior perf_begin returns a typed error, does not throw',
        () async {
      final developer.ServiceExtensionResponse response =
          await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});

      expect(response.result, isNull);
      expect(response.errorDetail, contains('perf_begin'));
      final Map<String, dynamic> detail =
          jsonDecode(response.errorDetail!) as Map<String, dynamic>;
      expect((detail['envelope'] as Map<String, dynamic>)['type'], isNotNull);
    });

    test('restores every flag to its PRIOR value, not to false', () async {
      // A host with build profiling already on (a DevTools user, a nested
      // harness) must get it back; forcing false would silently turn off
      // something dusk never owned.
      debugProfileBuildsEnabled = true;
      debugProfileLayoutsEnabled = true;
      FlutterTimeline.debugCollectionEnabled = true;

      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'phases': 'true'},
      );
      framePerfReader = () => <String, Object?>{
            'frames': _fixtureFrames,
            'livenessCounter': 5,
          };
      await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});

      expect(debugProfileBuildsEnabled, isTrue);
      expect(debugProfileLayoutsEnabled, isTrue);
      expect(FlutterTimeline.debugCollectionEnabled, isTrue);
      // The two dusk did own on this run go back off.
      expect(debugProfileBuildsEnabledUserWidgets, isFalse);
      expect(debugProfilePaintsEnabled, isFalse);
    });

    test('calls perfSessionEndHook so wind stops counting after the session',
        () async {
      int endCalls = 0;
      perfSessionEndHook = () => endCalls++;

      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      framePerfReader = () => <String, Object?>{
            'frames': _fixtureFrames,
            'livenessCounter': 3,
          };
      await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});

      expect(endCalls, 1);
    });

    test(
        'refuses with no metrics block when the liveness counter did not '
        'advance', () async {
      // The engine is not rendering: the reader answers the same counter on
      // both reads. Every metric would be a zero that reads as "fast".
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[],
            'livenessCounter': 7,
          };

      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      final Map<String, dynamic> payload = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      expect(payload['refused'], isTrue);
      expect(payload['reason'], contains('liveness counter'));
      expect(payload['liveness'], <String, dynamic>{
        'baseline': 7,
        'final': 7,
        'advanced': 0,
      });
      // A refusal carries no numbers at all; a partial report would be read
      // as a report.
      expect(payload.containsKey('frameSummary'), isFalse);
      expect(payload.containsKey('blockAttribution'), isFalse);
      expect(payload.containsKey('wind'), isFalse);
      expect(payload.containsKey('magic'), isFalse);
    });

    test('a throwing begin hook restores the flags immediately, without '
        'waiting for a perf_end', () async {
      // Both `perfSessionBeginHook` and `framePerfReader` are assigned in
      // another repository, so both can throw. The session is installed before
      // any flag is written precisely so the catch can hand the
      // instrumentation straight back: waiting for a `perf_end` that a crashed
      // agent may never send would leave profiling on with no recovery short
      // of a hot restart, which the plan forbids outright.
      FlutterTimeline.debugCollectionEnabled = false;
      debugProfileBuildsEnabled = false;
      perfSessionBeginHook = () => throw StateError('host wiring is broken');

      final developer.ServiceExtensionResponse begin =
          await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});

      expect(begin.result, isNull, reason: 'the failure must surface');
      expect(FlutterTimeline.debugCollectionEnabled, isFalse);
      expect(debugProfileBuildsEnabled, isFalse);
      expect(debugProfileBuildsEnabledUserWidgets, isFalse);
      expect(debugProfileLayoutsEnabled, isFalse);
      expect(debugProfilePaintsEnabled, isFalse);
    });

    test('a failed begin leaves NO session, so a later perf_end cannot report '
        'over an uncleared buffer', () async {
      // The mutant this replaces: with a session left open carrying a baseline
      // of 0, `advanced = final - 0` equals the absolute counter, which is in
      // the thousands on a real app. It sails past the stalled-engine
      // threshold and reports frames nobody drove, out of a buffer the
      // throwing hook never reached `clearFramePerf()` to empty. A stub pinned
      // to a counter of 0 cannot express that; this one is deliberately live.
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[
              _frame(frameNumber: 900, buildMicros: 5000, rasterMicros: 2000),
            ],
            'livenessCounter': 4213,
          };
      perfSessionBeginHook = () => throw StateError('host wiring is broken');

      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      final developer.ServiceExtensionResponse end =
          await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});

      expect(end.result, isNull, reason: 'no session is open to report on');
      expect(end.errorDetail, contains('perf_begin'));
    });

    test('refuses when the counter advanced by exactly one, which is what a '
        'backgrounded page produces', () async {
      // Measured, not hypothesised. Driving a scroll against a hidden Chrome
      // page and closing the session read `advanced: 1`: the engine emits one
      // frame at the moment it is backgrounded and then nothing. A threshold
      // of zero reported on that as though the page were healthy, which is
      // the exact table of near-zeros this refusal exists to prevent.
      //
      // Stubbing the reader to a CONSTANT is what let the defect through the
      // first time: it can only ever produce advanced == 0, so it never met
      // the value a real stalled engine actually returns.
      int reads = 0;
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[
              <String, Object?>{
                'frameNumber': 1,
                'buildMicros': 5000,
                'rasterMicros': 2000,
                'vsyncOverheadMicros': 1000,
                'totalSpanMicros': 8000,
                'blocks': <String, Object?>{},
              },
            ],
            'livenessCounter': 40 + (reads++ > 0 ? 1 : 0),
          };

      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      final Map<String, dynamic> payload = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      expect(payload['refused'], isTrue);
      expect((payload['liveness']! as Map<String, dynamic>)['advanced'], 1);
      // The frame list was NOT empty, so this cannot pass by accident on an
      // empty-buffer check: the refusal has to come from the counter.
      expect(payload.containsKey('frameSummary'), isFalse);
    });

    test('the refusal is its own field, independent of the warnings block',
        () async {
      // `duskResult` stamps `warnings` from SchedulerBinding.framesEnabled,
      // which was measured reporting true on a hidden Chrome page. A reader
      // must be able to tell the two signals apart, so `refused` has to move
      // while the warnings key does not.
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[],
            'livenessCounter': 7,
          };
      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      final Map<String, dynamic> refusal = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      framePerfReader = () => <String, Object?>{
            'frames': _fixtureFrames,
            'livenessCounter': 99,
          };
      final Map<String, dynamic> report = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      expect(refusal['refused'], isTrue);
      expect(report['refused'], isFalse);
      expect(
        refusal.containsKey('warnings'),
        report.containsKey('warnings'),
        reason: 'the frame-production warning must not be what distinguishes '
            'a refusal from a report',
      );
    });

    test('the refusal still restores the flags and closes the session',
        () async {
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[],
            'livenessCounter': 7,
          };

      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'phases': 'true'},
      );
      await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});

      expect(debugProfileBuildsEnabled, isFalse);
      expect(debugProfilePaintsEnabled, isFalse);
      expect(FlutterTimeline.debugCollectionEnabled, isFalse);

      // Session closed: a second end has nothing to close.
      final developer.ServiceExtensionResponse second =
          await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});
      expect(second.result, isNull);
    });

    test('carries the frame summary, the wind section and the magic section',
        () async {
      WindDebugRegistry.registerPerf(_FakeWindPerfResolver());
      perfExtrasReader = () => <String, Object?>{
            'controllerNotifies': <String, int>{'MonitorController': 12},
            'routeTransitions': <Map<String, Object?>>[
              <String, Object?>{'route': '/monitors', 'micros': 4200},
            ],
          };

      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      framePerfReader = () => <String, Object?>{
            'frames': _fixtureFrames,
            'livenessCounter': 44,
          };
      final Map<String, dynamic> payload = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      expect(payload['refused'], isFalse);
      expect(payload['liveness'], <String, dynamic>{
        'baseline': 0,
        'final': 44,
        'advanced': 44,
      });

      final Map<String, dynamic> summary =
          payload['frameSummary'] as Map<String, dynamic>;
      expect(summary['frame_count'], 2);
      expect(summary['worst_frame_build_time_millis'], 20.0);
      expect(summary['missed_frame_build_budget_count'], 1);
      expect(summary['dropped_frame_count'], 0);
      expect(summary['worst_frames'], isA<List<dynamic>>());

      expect(
        payload['wind'],
        containsPair('cacheBypasses', 40),
      );
      final Map<String, dynamic> magic =
          payload['magic'] as Map<String, dynamic>;
      expect(
        magic['controllerNotifies'],
        <String, dynamic>{'MonitorController': 12},
      );
      expect((magic['routeTransitions'] as List<dynamic>), hasLength(1));

      // Flutter's own docs say the instrumentation overhead is significant
      // relative to the work measured; the payload has to say so itself.
      expect(payload['note'], contains('indicative'));
    });

    test('ranks block attribution across the whole session, not per frame',
        () async {
      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      framePerfReader = () => <String, Object?>{
            'frames': _fixtureFrames,
            'livenessCounter': 2,
          };
      final Map<String, dynamic> payload = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      final List<dynamic> blocks = payload['blockAttribution'] as List<dynamic>;
      expect(blocks, hasLength(3));
      expect(blocks.first, <String, dynamic>{
        'name': 'MonitorRow',
        'micros': 10200,
        'count': 10,
        'frames': 2,
      });
      expect((blocks[1] as Map<String, dynamic>)['name'], 'WText');
      expect((blocks[2] as Map<String, dynamic>)['name'], 'WDiv');
    });

    test('reports a null wind section when no perf resolver is registered',
        () async {
      await duskPerfBeginHandler('ext.dusk.perf_begin', <String, String>{});
      framePerfReader = () => <String, Object?>{
            'frames': _fixtureFrames,
            'livenessCounter': 2,
          };
      final Map<String, dynamic> payload = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      // Null rather than a map of zeros: "wind never registered" and "wind
      // registered and counted nothing" are different findings.
      expect(payload.containsKey('wind'), isTrue);
      expect(payload['wind'], isNull);
    });
  });
}
