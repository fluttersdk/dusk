import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/dusk_response.dart';
import '../utils/error_envelope.dart';
import '../utils/perf_interaction.dart';
import '../utils/perf_readers.dart';
import 'ext_perf.dart';

/// Registers `ext.dusk.perf_trace`. Idempotent via
/// [registerExtensionIdempotent]; call once from `registerAllDuskExtensions()`.
void registerPerfTraceExtension() {
  registerExtensionIdempotent('ext.dusk.perf_trace', duskPerfTraceHandler);
}

/// The one process every event is filed under.
const int _kPid = 1;

/// Tracks dusk fills itself, listed first so they sit at the top.
const String _kInteractionTrack = 'interactions';
const String _kFrameTrack = 'frames';

/// Handler for `ext.dusk.perf_trace`: the most recent closed session's
/// timeline as Chrome Trace Event JSON, which ui.perfetto.dev and
/// chrome://tracing open as is.
///
/// Params (all string-valued):
/// - `token` (optional): the session's `sessionToken`. When given it must
///   name the most recent closed session, the only one kept.
///
/// Response JSON:
/// ```json
/// {
///   "sessionToken": "perf-1",
///   "traceEvents": [
///     {"ph": "X", "cat": "interaction", "name": "tap", "ts": 812345,
///      "dur": 412000, "pid": 1, "tid": 1, "args": {"id": "i1", "target": "e3"}},
///     {"ph": "b", "cat": "http", "name": "GET /monitors", "id": "r1", "...": 0}
///   ],
///   "displayTimeUnit": "ms",
///   "otherData": {"sessionToken": "perf-1", "startUs": 800000,
///                 "endUs": 2900000, "interactions": 3, "frames": 45,
///                 "rows": 12, "skippedRows": 0}
/// }
/// ```
///
/// The frames and the host rows are read NOW, through [framePerfReader] and
/// [perfTimelineReader], and cut to the session window; the interactions are
/// dusk's own. So export before the next `perf_begin`, whose host hook clears
/// those buffers: while a session is open this answers an error rather than a
/// trace that silently lost its frames. Every miss is an error naming what to
/// do instead, and a throwing host reader is an error envelope, never a throw
/// across the VM Service boundary.
Future<developer.ServiceExtensionResponse> duskPerfTraceHandler(
  String method,
  Map<String, String> params,
) async {
  // 1. Name the session, or say why there is none to export.
  final String? token = params['token'];
  final String? closed = lastClosedPerfToken;
  final ({int startUs, int endUs})? window = lastClosedPerfWindow;
  final String? problem = switch (closed) {
    null => 'no closed perf session to export. Run ext.dusk.perf_begin, '
        'drive the interaction, then ext.dusk.perf_end.',
    _ when token != null && token != closed =>
      'session $token is not held; only the most recent closed session '
          '($closed) is kept. Export it, or rerun the session.',
    _ when perfSessionOpen =>
      'a perf session is open, and its perf_begin cleared the frames the '
          'trace of $closed would read. Close it with ext.dusk.perf_end and '
          'export that session instead.',
    _ => null,
  };
  if (problem != null || window == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.perf_trace: $problem',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }

  try {
    // 2. Read the host buffers; both readers are assigned in another
    //    repository and can throw.
    final Object? rawFrames = framePerfReader()['frames'];
    final List<Map<String, Object?>> rows = perfTimelineReader();

    // 3. Build the trace from the window alone.
    return duskResult(<String, dynamic>{
      'sessionToken': closed,
      ...buildPerfTrace(
        token: closed!,
        startUs: window.startUs,
        endUs: window.endUs,
        interactions: perfInteractionsBetween(window.startUs, window.endUs)
            .map((PerfInteraction i) => i.toJson())
            .toList(),
        frames: rawFrames is List<Object?>
            ? rawFrames.whereType<Map<String, Object?>>().toList()
            : const <Map<String, Object?>>[],
        rows: rows,
      ),
    });
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.perf_trace: unexpected error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.perf_trace: $e',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }
}

/// Builds the Chrome Trace Event JSON object for one session window.
///
/// [interactions] are `PerfInteraction.toJson()` maps, [frames]
/// `framePerfReader` rows, [rows] `perfTimelineReader` rows (schema on that
/// pointer). Anything starting outside [startUs]..[endUs] is left out;
/// anything still open at [endUs] ends there.
///
/// - Interactions and frames become `X` slices on the `interactions` and
///   `frames` tracks; a frame is placed at `vsyncStartUs` for
///   `totalSpanMicros`, and one without `vsyncStartUs` is left out.
/// - A host `span` with an `id` becomes an async `b`/`e` pair (`cat` is its
///   track), one without an `id` an `X` slice, an `instant` an `i` event, a
///   `counter` a `C` event.
///
/// `X` slices must nest on their track for Perfetto to draw them
/// (https://perfetto.dev/docs/getting-started/other-formats), and two overlap
/// in ordinary use: a tap before the last one settled, a frame whose build
/// starts while the previous one rasterizes. A slice that would straddle
/// another moves to an overflow lane, `<track> (2)`, rather than being
/// trimmed: the durations stay true.
@visibleForTesting
Map<String, Object?> buildPerfTrace({
  required String token,
  required int startUs,
  required int endUs,
  required List<Map<String, Object?>> interactions,
  required List<Map<String, Object?>> frames,
  required List<Map<String, Object?>> rows,
}) {
  bool inWindow(int us) => us >= startUs && us <= endUs;
  int endOf(int? us) => us == null || us > endUs ? endUs : us;

  final _Tracks tracks = _Tracks()
    ..declare(_kInteractionTrack)
    ..declare(_kFrameTrack);
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  // 1. Dusk's own interactions.
  int interactionCount = 0;
  for (final Map<String, Object?> interaction in interactions) {
    final int start = _asInt(interaction['startUs']);
    if (!inWindow(start)) continue;
    interactionCount++;
    tracks.slice(
      _kInteractionTrack,
      _Slice(
        start,
        endOf(_asNullableInt(interaction['closedAtUs'])),
        <String, Object?>{
          'cat': 'interaction',
          'name': interaction['verb'],
          'args': <String, Object?>{
            'id': interaction['id'],
            'target': interaction['target'],
          },
        },
      ),
    );
  }

  // 2. Frames, placed by vsync start.
  int frameCount = 0;
  for (final Map<String, Object?> frame in frames) {
    final int? start = _asNullableInt(frame['vsyncStartUs']);
    if (start == null || !inWindow(start)) continue;
    frameCount++;
    tracks.slice(
      _kFrameTrack,
      _Slice(
        start,
        start + _asInt(frame['totalSpanMicros']),
        <String, Object?>{
          'cat': 'frame',
          'name': 'Frame ${frame['frameNumber']}',
          'args': <String, Object?>{
            'frameNumber': frame['frameNumber'],
            'buildMs': _asInt(frame['buildMicros']) / 1000,
            'rasterMs': _asInt(frame['rasterMicros']) / 1000,
            ..._links(frame),
          },
        },
      ),
    );
  }

  // 3. The host's rows, by kind.
  int rowCount = 0;
  int skipped = 0;
  for (final Map<String, Object?> row in rows) {
    final Object? kind = row['kind'];
    final Object? track = row['track'];
    final Object? name = row['name'];
    final Object? start = row['startUs'];
    final Object? value = row['value'];
    if (track is! String ||
        name is! String ||
        start is! int ||
        (kind == 'counter' && value is! num) ||
        (kind != 'span' && kind != 'instant' && kind != 'counter')) {
      skipped++;
      continue;
    }
    if (!inWindow(start)) continue;
    rowCount++;

    final Object? rawArgs = row['args'];
    final Map<String, Object?> args = <String, Object?>{
      if (rawArgs is Map<Object?, Object?>)
        for (final MapEntry<Object?, Object?> e in rawArgs.entries)
          '${e.key}': e.value,
      ..._links(row),
    };
    final Object? id = row['id'];
    final int end = endOf(_asNullableInt(row['endUs']));

    switch (kind) {
      case 'span' when id != null:
        final Map<String, Object?> pair = <String, Object?>{
          'cat': track,
          'name': name,
          'id': '$id',
          'pid': _kPid,
          'tid': tracks.tid(track),
        };
        events
          ..add(<String, Object?>{
            ...pair,
            'ph': 'b',
            'ts': start,
            'args': args,
          })
          ..add(<String, Object?>{...pair, 'ph': 'e', 'ts': end});
      case 'span':
        tracks.slice(
          track,
          _Slice(start, end, <String, Object?>{
            'cat': track,
            'name': name,
            'args': args,
          }),
        );
      case 'instant':
        events.add(<String, Object?>{
          'ph': 'i',
          's': 't',
          'cat': track,
          'name': name,
          'ts': start,
          'pid': _kPid,
          'tid': tracks.tid(track),
          'args': args,
        });
      case 'counter':
        events.add(<String, Object?>{
          'ph': 'C',
          'cat': track,
          'name': name,
          'ts': start,
          'pid': _kPid,
          'args': <String, Object?>{'value': value},
        });
    }
  }

  // 4. Lanes resolve last, once every slice of a track is known.
  return <String, Object?>{
    'traceEvents': <Map<String, Object?>>[
      <String, Object?>{
        'ph': 'M',
        'name': 'process_name',
        'pid': _kPid,
        'args': <String, Object?>{'name': 'fluttersdk_dusk $token'},
      },
      ...tracks.emit(),
      ...events,
    ],
    'displayTimeUnit': 'ms',
    'otherData': <String, Object?>{
      'sessionToken': token,
      'startUs': startUs,
      'endUs': endUs,
      'interactions': interactionCount,
      'frames': frameCount,
      'rows': rowCount,
      'skippedRows': skipped,
    },
  };
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// One synchronous slice waiting for its lane.
final class _Slice {
  const _Slice(this.start, this.end, this.event);

  final int start;
  final int end;

  /// `cat`, `name` and `args`; the rest is filled in on emit.
  final Map<String, Object?> event;
}

/// Tracks in first-use order, each owning a thread id per lane, plus the `X`
/// slices placed on them.
final class _Tracks {
  final Map<String, int> _tids = <String, int>{};
  final Map<String, List<_Slice>> _slices = <String, List<_Slice>>{};

  void declare(String track) => tid(track);

  /// The thread id of [track]'s first lane, or of the lane named [track]
  /// when it is an overflow lane.
  int tid(String track) => _tids.putIfAbsent(track, () => _tids.length + 1);

  void slice(String track, _Slice slice) {
    tid(track);
    _slices.putIfAbsent(track, () => <_Slice>[]).add(slice);
  }

  /// Places every slice on the first lane of its track where it nests, then
  /// returns the thread-name metadata and the `X` events.
  List<Map<String, Object?>> emit() {
    final List<Map<String, Object?>> placed = <Map<String, Object?>>[];
    for (final MapEntry<String, List<_Slice>> entry
        in Map<String, List<_Slice>>.of(_slices).entries) {
      // Longest first among equal starts, so a parent opens before its child.
      final List<_Slice> ordered = List<_Slice>.of(entry.value)
        ..sort((_Slice a, _Slice b) {
          final int byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : b.end.compareTo(a.end);
        });
      final List<List<int>> lanes = <List<int>>[];
      for (final _Slice slice in ordered) {
        final int lane = _laneFor(lanes, slice);
        final String name =
            lane == 0 ? entry.key : '${entry.key} (${lane + 1})';
        placed.add(<String, Object?>{
          ...slice.event,
          'ph': 'X',
          'ts': slice.start,
          'dur': slice.end - slice.start,
          'pid': _kPid,
          'tid': tid(name),
        });
      }
    }
    return <Map<String, Object?>>[
      for (final MapEntry<String, int> t in _tids.entries)
        <String, Object?>{
          'ph': 'M',
          'name': 'thread_name',
          'pid': _kPid,
          'tid': t.value,
          'args': <String, Object?>{'name': t.key},
        },
      ...placed,
    ];
  }

  /// The first lane [slice] nests in, opening a new one when none fits. Each
  /// lane is a stack of the ends of the slices still open on it: a slice
  /// fits when, after closing everything that ended by its start, it ends no
  /// later than the innermost slice still open.
  static int _laneFor(List<List<int>> lanes, _Slice slice) {
    for (int i = 0; i < lanes.length; i++) {
      final List<int> open = lanes[i];
      while (open.isNotEmpty && open.last <= slice.start) {
        open.removeLast();
      }
      if (open.isEmpty || slice.end <= open.last) {
        open.add(slice.end);
        return i;
      }
    }
    lanes.add(<int>[slice.end]);
    return lanes.length - 1;
  }
}

/// The causal link a row or frame carries, when it carries one.
Map<String, Object?> _links(Map<String, Object?> source) => <String, Object?>{
      if (source['interactionId'] != null)
        'interactionId': source['interactionId'],
      if (source['linkedBy'] != null) 'linkedBy': source['linkedBy'],
    };

int _asInt(Object? value) => value is num ? value.toInt() : 0;

int? _asNullableInt(Object? value) => value is num ? value.toInt() : null;
