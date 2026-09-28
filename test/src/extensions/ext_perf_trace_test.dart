import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_perf.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_perf_trace.dart';
import 'package:fluttersdk_dusk/src/utils/perf_insights.dart';
import 'package:fluttersdk_dusk/src/utils/perf_interaction.dart';
import 'package:fluttersdk_dusk/src/utils/perf_readers.dart';

const int _start = 1000;
const int _end = 100000;

final List<Map<String, Object?>> _interactions = <Map<String, Object?>>[
  <String, Object?>{
    'id': 'i0',
    'verb': 'tap',
    'target': 'e1',
    'startUs': 500,
    'closedAtUs': 900,
  },
  <String, Object?>{
    'id': 'i1',
    'verb': 'tap',
    'target': 'e3',
    'startUs': 2000,
    'closedAtUs': 40000,
  },
  // Starts before i1 settles and ends after it: an X slice on i1's track
  // would straddle it.
  <String, Object?>{
    'id': 'i2',
    'verb': 'type',
    'target': 'e4',
    'startUs': 30000,
    'closedAtUs': 60000,
  },
  // Never settled before the session ended.
  <String, Object?>{
    'id': 'i3',
    'verb': 'scroll',
    'target': null,
    'startUs': 90000,
    'closedAtUs': null,
  },
];

final List<Map<String, Object?>> _frames = <Map<String, Object?>>[
  <String, Object?>{
    'frameNumber': 1,
    'vsyncStartUs': 3000,
    'totalSpanMicros': 20000,
    'buildMicros': 8000,
    'rasterMicros': 9000,
    'interactionId': 'i1',
    'linkedBy': 'frame',
  },
  // Pipelined: its build starts while frame 1 still rasterizes.
  <String, Object?>{
    'frameNumber': 2,
    'vsyncStartUs': 19700,
    'totalSpanMicros': 20000,
    'buildMicros': 6000,
    'rasterMicros': 7000,
  },
  // No vsync timestamp: nothing to place it at.
  <String, Object?>{
    'frameNumber': 3,
    'totalSpanMicros': 20000,
  },
  <String, Object?>{
    'frameNumber': 4,
    'vsyncStartUs': 200000,
    'totalSpanMicros': 20000,
  },
];

final List<Map<String, Object?>> _rows = <Map<String, Object?>>[
  <String, Object?>{
    'kind': 'span',
    'track': 'http',
    'name': 'GET /monitors',
    'startUs': 5000,
    'endUs': 50000,
    'id': 'r1',
    'interactionId': 'i1',
    'linkedBy': 'zone',
    'args': <String, Object?>{'status': 200},
  },
  <String, Object?>{
    'kind': 'span',
    'track': 'http',
    'name': 'GET /teams',
    'startUs': 10000,
    'endUs': 30000,
    'id': 'r2',
  },
  <String, Object?>{
    'kind': 'span',
    'track': 'http',
    'name': 'GET /stream',
    'startUs': 80000,
    'id': 'r3',
  },
  <String, Object?>{
    'kind': 'span',
    'track': 'magic',
    'name': 'MonitorsController.notify',
    'startUs': 6000,
    'endUs': 9000,
  },
  <String, Object?>{
    'kind': 'span',
    'track': 'magic',
    'name': 'Nested',
    'startUs': 6500,
    'endUs': 7000,
  },
  <String, Object?>{
    'kind': 'span',
    'track': 'magic',
    'name': 'Straddle',
    'startUs': 8000,
    'endUs': 12000,
  },
  <String, Object?>{
    'kind': 'instant',
    'track': 'magic',
    'name': 'route /monitors',
    'startUs': 7000,
  },
  <String, Object?>{
    'kind': 'counter',
    'track': 'wind',
    'name': 'wDivBuilds',
    'startUs': 7000,
    'value': 12,
  },
  <String, Object?>{
    'kind': 'span',
    'track': 'http',
    'name': 'before the session',
    'startUs': 500,
    'endUs': 900,
    'id': 'r0',
  },
  // Three rows no exporter can place.
  <String, Object?>{'kind': 'span', 'track': 'x'},
  <String, Object?>{
    'kind': 'flow',
    'track': 'x',
    'name': 'n',
    'startUs': 2000,
  },
  <String, Object?>{
    'kind': 'counter',
    'track': 'wind',
    'name': 'noValue',
    'startUs': 2000,
  },
];

List<Map<String, Object?>> _events(Map<String, Object?> trace) =>
    (trace['traceEvents']! as List<Object?>).cast<Map<String, Object?>>();

List<Map<String, Object?>> _phase(Map<String, Object?> trace, String ph) =>
    _events(trace).where((Map<String, Object?> e) => e['ph'] == ph).toList();

Map<int, String> _threadNames(Map<String, Object?> trace) => <int, String>{
      for (final Map<String, Object?> e in _phase(trace, 'M'))
        if (e['name'] == 'thread_name')
          e['tid']! as int:
              (e['args']! as Map<String, Object?>)['name']! as String,
    };

/// Every `B` has a matching `E` on its own `tid`, in stack order, and every
/// `X` on a `tid` nests inside or sits apart from the others there: the rule
/// Perfetto draws a synchronous track by.
void _expectSyncSlicesNest(Map<String, Object?> trace) {
  final Map<int, List<Map<String, Object?>>> byTid =
      <int, List<Map<String, Object?>>>{};
  for (final Map<String, Object?> e in _events(trace)) {
    if (e['ph'] == 'B' || e['ph'] == 'E' || e['ph'] == 'X') {
      byTid
          .putIfAbsent(e['tid']! as int, () => <Map<String, Object?>>[])
          .add(e);
    }
  }
  for (final MapEntry<int, List<Map<String, Object?>>> entry in byTid.entries) {
    final List<String> open = <String>[];
    for (final Map<String, Object?> e in entry.value) {
      if (e['ph'] == 'B') open.add(e['name']! as String);
      if (e['ph'] == 'E') {
        expect(open, isNotEmpty, reason: 'E without B on tid ${entry.key}');
        open.removeLast();
      }
    }
    expect(open, isEmpty, reason: 'B without E on tid ${entry.key}');

    final List<(int, int)> slices = <(int, int)>[
      for (final Map<String, Object?> e in entry.value)
        if (e['ph'] == 'X')
          (e['ts']! as int, (e['ts']! as int) + (e['dur']! as int)),
    ];
    for (final (int, int) a in slices) {
      for (final (int, int) b in slices) {
        final bool apart = a.$2 <= b.$1 || b.$2 <= a.$1;
        final bool aInB = b.$1 <= a.$1 && a.$2 <= b.$2;
        final bool bInA = a.$1 <= b.$1 && b.$2 <= a.$2;
        expect(
          apart || aInB || bInA,
          isTrue,
          reason: 'X slices $a and $b straddle on tid ${entry.key}',
        );
      }
    }
  }
}

/// Every `b` has exactly one `e` with the same `cat` and `id`, no earlier
/// than it.
void _expectAsyncPairsMatch(Map<String, Object?> trace) {
  final List<Map<String, Object?>> begins = _phase(trace, 'b');
  final List<Map<String, Object?>> ends = _phase(trace, 'e');
  expect(begins.length, ends.length);
  for (final Map<String, Object?> b in begins) {
    final List<Map<String, Object?>> matching = ends
        .where(
          (Map<String, Object?> e) =>
              e['id'] == b['id'] && e['cat'] == b['cat'],
        )
        .toList();
    expect(matching, hasLength(1), reason: 'b ${b['id']} has no single e');
    expect(
        matching.single['ts']! as int, greaterThanOrEqualTo(b['ts']! as int));
  }
}

Map<String, Object?> _build() => buildPerfTrace(
      token: 'perf-7',
      startUs: _start,
      endUs: _end,
      interactions: _interactions,
      frames: _frames,
      rows: _rows,
    );

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

  group('buildPerfTrace()', () {
    test('every B has an E on its tid, X slices nest, every b has its e', () {
      final Map<String, Object?> trace = _build();

      expect(_phase(trace, 'X'), isNotEmpty);
      _expectSyncSlicesNest(trace);
      _expectAsyncPairsMatch(trace);
    });

    test('carries the interactions as X slices, splitting a straddle', () {
      final Map<String, Object?> trace = _build();
      final Map<int, String> threads = _threadNames(trace);
      final List<Map<String, Object?>> slices = _phase(trace, 'X')
          .where((Map<String, Object?> e) => e['cat'] == 'interaction')
          .toList();

      expect(
        slices.map((Map<String, Object?> e) => e['name']),
        <String>['tap', 'type', 'scroll'],
        reason: 'i0 started before the session and is not in it',
      );
      final Map<String, Object?> tap = slices[0];
      expect(tap['ts'], 2000);
      expect(tap['dur'], 38000);
      expect(
        tap['args'],
        <String, Object?>{'id': 'i1', 'target': 'e3'},
      );
      expect(threads[tap['tid']], 'interactions');
      expect(slices[1]['tid'], isNot(tap['tid']));
      expect(threads[slices[1]['tid']], 'interactions (2)');
      // Still settling when the session closed: it ends at the session end.
      expect(
        (slices[2]['ts']! as int) + (slices[2]['dur']! as int),
        _end,
      );
    });

    test('carries the frames placed by vsync start, pipelining split', () {
      final Map<String, Object?> trace = _build();
      final Map<int, String> threads = _threadNames(trace);
      final List<Map<String, Object?>> frames = _phase(trace, 'X')
          .where((Map<String, Object?> e) => e['cat'] == 'frame')
          .toList();

      expect(frames, hasLength(2), reason: 'frame 3 has no vsync, 4 is late');
      expect(frames[0]['ts'], 3000);
      expect(frames[0]['dur'], 20000);
      expect(
        frames[0]['args'],
        <String, Object?>{
          'frameNumber': 1,
          'buildMs': 8.0,
          'rasterMs': 9.0,
          'interactionId': 'i1',
          'linkedBy': 'frame',
        },
      );
      expect(threads[frames[0]['tid']], 'frames');
      expect(threads[frames[1]['tid']], 'frames (2)');
    });

    test('maps host rows by kind: id spans b/e, others X, i and C', () {
      final Map<String, Object?> trace = _build();
      final Map<int, String> threads = _threadNames(trace);

      final List<Map<String, Object?>> begins = _phase(trace, 'b');
      expect(
        begins.map((Map<String, Object?> e) => e['id']),
        <String>['r1', 'r2', 'r3'],
      );
      expect(begins.first['cat'], 'http');
      expect(begins.first['name'], 'GET /monitors');
      expect(
        begins.first['args'],
        <String, Object?>{
          'status': 200,
          'interactionId': 'i1',
          'linkedBy': 'zone',
        },
      );
      final Map<String, Object?> openEnd = _phase(trace, 'e')
          .singleWhere((Map<String, Object?> e) => e['id'] == 'r3');
      expect(openEnd['ts'], _end, reason: 'a span still running ends there');

      final List<Map<String, Object?>> magic = _phase(trace, 'X')
          .where((Map<String, Object?> e) => e['cat'] == 'magic')
          .toList();
      expect(
        magic.map((Map<String, Object?> e) => e['name']),
        <String>['MonitorsController.notify', 'Nested', 'Straddle'],
      );
      expect(magic[1]['tid'], magic[0]['tid'], reason: 'Nested nests');
      expect(threads[magic[2]['tid']], 'magic (2)');

      final Map<String, Object?> instant = _phase(trace, 'i').single;
      expect(instant['name'], 'route /monitors');
      expect(instant['s'], 't');
      expect(threads[instant['tid']], 'magic');

      final Map<String, Object?> counter = _phase(trace, 'C').single;
      expect(counter['name'], 'wDivBuilds');
      expect(counter['cat'], 'wind');
      expect(counter['args'], <String, Object?>{'value': 12});
    });

    test('counts what it could not place and names the window', () {
      final Map<String, Object?> trace = _build();

      expect(trace['displayTimeUnit'], 'ms');
      expect(
        trace['otherData'],
        <String, Object?>{
          'sessionToken': 'perf-7',
          'startUs': _start,
          'endUs': _end,
          'interactions': 3,
          'frames': 2,
          'framesOutsideWindow': 1,
          'rows': 8,
          'skippedRows': 3,
        },
      );
      for (final Map<String, Object?> e in _events(trace)) {
        expect(e['pid'], 1);
        expect(e['name'], isNot('before the session'));
      }
      expect(
        _phase(trace, 'M').where(
          (Map<String, Object?> e) => e['name'] == 'process_name',
        ),
        hasLength(1),
      );
    });
  });

  group('ext.dusk.perf_trace', () {
    setUp(() {
      resetPerfSessionForTesting();
      resetClosedPerfSessionForTesting();
      resetPerfInteractionsForTesting();
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[],
            'livenessCounter': 0,
          };
      perfExtrasReader = () => <String, Object?>{};
      perfTimelineReader = () => <Map<String, Object?>>[];
      perfSessionBeginHook = (PerfMode mode) {};
      perfSessionEndHook = () {};
    });

    tearDown(() {
      resetPerfSessionForTesting();
      resetClosedPerfSessionForTesting();
    });

    test('before any session closed it is an error naming perf_end', () async {
      final developer.ServiceExtensionResponse response =
          await duskPerfTraceHandler('ext.dusk.perf_trace', <String, String>{});

      expect(response.result, isNull);
      expect(response.errorDetail, contains('perf_end'));
    });

    test('a stale token is an error naming the session that is held', () async {
      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'mode': 'timing'},
      );
      final Map<String, dynamic> end = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      final developer.ServiceExtensionResponse response =
          await duskPerfTraceHandler(
        'ext.dusk.perf_trace',
        <String, String>{'token': 'perf-0'},
      );

      expect(response.result, isNull);
      expect(response.errorDetail, contains(end['sessionToken'] as String));
    });

    test('an open session is an error: its perf_begin cleared the buffers',
        () async {
      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'mode': 'timing'},
      );
      await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});
      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'mode': 'timing'},
      );

      final developer.ServiceExtensionResponse response =
          await duskPerfTraceHandler('ext.dusk.perf_trace', <String, String>{});

      expect(response.result, isNull);
      expect(response.errorDetail, contains('perf_end'));
    });

    test('a throwing host reader is an error envelope, never a throw',
        () async {
      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'mode': 'timing'},
      );
      await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{});
      perfTimelineReader = () => throw StateError('host wiring is broken');

      final developer.ServiceExtensionResponse response =
          await duskPerfTraceHandler('ext.dusk.perf_trace', <String, String>{});

      expect(response.result, isNull);
      expect(response.errorDetail, contains('host wiring is broken'));
    });

    testWidgets(
        "exports the closed session's interactions, frames and host rows",
        (WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await duskPerfBeginHandler(
        'ext.dusk.perf_begin',
        <String, String>{'mode': 'timing'},
      );
      await runPerfInteraction<void>('tap', 'e7', () async {});
      await tester.pump(const Duration(milliseconds: 500));
      final int at = FlutterTimeline.now;
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[
              <String, Object?>{
                'frameNumber': 1,
                'vsyncStartUs': at,
                'totalSpanMicros': 4000,
                'buildMicros': 2000,
                'rasterMicros': 1000,
              },
            ],
            'livenessCounter': 0,
          };
      perfTimelineReader = () => <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'span',
              'track': 'http',
              'name': 'GET /monitors',
              'startUs': at,
              'endUs': at + 100,
              'id': 'r1',
            },
          ];
      final Map<String, dynamic> end = _decode(
        await duskPerfEndHandler('ext.dusk.perf_end', <String, String>{}),
      );

      final Map<String, dynamic> trace = _decode(
        await duskPerfTraceHandler(
          'ext.dusk.perf_trace',
          <String, String>{'token': end['sessionToken'] as String},
        ),
      );

      expect(trace['sessionToken'], end['sessionToken']);
      final List<Map<String, Object?>> events =
          (trace['traceEvents'] as List<dynamic>).cast<Map<String, Object?>>();
      final Map<String, Object?> tap = events.singleWhere(
        (Map<String, Object?> e) => e['cat'] == 'interaction',
      );
      expect(tap['name'], 'tap');
      expect((tap['args']! as Map<String, Object?>)['target'], 'e7');
      expect(
        events.where((Map<String, Object?> e) => e['cat'] == 'frame'),
        hasLength(1),
      );
      expect(
        events.where((Map<String, Object?> e) => e['ph'] == 'b'),
        hasLength(1),
      );
    });

    test('registerPerfTraceExtension() is safe to call twice', () {
      expect(registerPerfTraceExtension, returnsNormally);
      expect(registerPerfTraceExtension, returnsNormally);
    });
  });
}
