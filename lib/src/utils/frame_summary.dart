/// The frame and block arithmetic behind `ext.dusk.perf_end`: percentile and
/// budget math over per-frame records, frame-number gap detection, and the
/// session-wide block aggregation the rankings are cut from.
///
/// Pure functions with no binding access, so they are trivially testable.
///
/// Every `frames` argument is `List<Map<String, Object?>>` shaped like
/// `FramePerfRecord.toJson()` (telescope repo): `frameNumber`, `buildMicros`,
/// `rasterMicros`, `blocks` (`{name: {micros, selfMicros, count}}`), `atUs`.
/// dusk cannot import telescope's record type (frozen contract #10), so the
/// input is the plain map shape rather than the typed record, and every read
/// tolerates a missing or mistyped key: the maps are built in another
/// repository, so a renamed key does not fail to compile, and one malformed
/// row must cost that row rather than the whole report.
library;

/// The frame budget every over-budget count and insight is judged against, in
/// milliseconds: one 60 Hz vsync interval. Stated in the report itself
/// (`summary.budgetMs`) so a reader never has to guess what "over budget"
/// meant.
const double kFrameBudgetMs = 16.7;

/// How many entries each ranked block list carries. The tail of a real
/// session is hundreds of one-off widget types; the head of the ranking is
/// what directs a fix, and `omitted` says how much was cut.
const int kRankedBlockLimit = 10;

/// [kFrameBudgetMs] in microseconds, the unit frame records arrive in.
const int kFrameBudgetMicros = 16700;

/// Summarizes [frames] into the frame block of the report, every duration in
/// milliseconds.
///
/// - `painted`: frame records Flutter reported timings for.
/// - `dropped`: frames missing from the `frameNumber` sequence. On web a
///   dropped scene is a missing frame number rather than a slow frame.
/// - `count`: `painted + dropped`, the frames the engine owed the session.
/// - `overBudget`: frames where EITHER thread exceeded [kFrameBudgetMs];
///   `overBudgetBuild` and `overBudgetRaster` split it by thread, which is
///   the first fork in any fix.
/// - `buildMs` / `rasterMs`: p50, p90, p99 and worst.
///
/// The comparison is strict, mirroring flutter_driver's `_countExceed`: a
/// frame at exactly the budget is not over it. An empty [frames] list returns
/// zeros rather than dividing by zero.
Map<String, Object?> summarizeFramePerf(List<Map<String, Object?>> frames) {
  final List<int> buildMicros =
      frames.map((Map<String, Object?> f) => _int(f['buildMicros'])).toList();
  final List<int> rasterMicros =
      frames.map((Map<String, Object?> f) => _int(f['rasterMicros'])).toList();

  int overBudget = 0;
  for (int i = 0; i < frames.length; i++) {
    if (_overBudget(buildMicros[i]) || _overBudget(rasterMicros[i])) {
      overBudget++;
    }
  }

  final int dropped = frameGaps(frames).fold<int>(
    0,
    (int sum, Map<String, Object?> gap) => sum + (gap['missing']! as int),
  );

  return <String, Object?>{
    'count': frames.length + dropped,
    'painted': frames.length,
    'dropped': dropped,
    'overBudget': overBudget,
    'overBudgetBuild': buildMicros.where(_overBudget).length,
    'overBudgetRaster': rasterMicros.where(_overBudget).length,
    'buildMs': _percentiles(buildMicros),
    'rasterMs': _percentiles(rasterMicros),
  };
}

/// Every gap in the `frameNumber` sequence of [frames], as
/// `{after, next, missing}`.
///
/// Rows with no numeric `frameNumber` leave the sequence rather than reading
/// as 0: substituting 0 for a missing POSITION manufactures a gap the size of
/// the number before it, which once reported 101 drops against a truth of 1.
/// A non-monotonic or duplicated pair contributes nothing, so the count never
/// goes negative.
List<Map<String, Object?>> frameGaps(List<Map<String, Object?>> frames) {
  final List<int> numbers = frames
      .map((Map<String, Object?> f) => f['frameNumber'])
      .whereType<num>()
      .map((num n) => n.toInt())
      .toList();

  final List<Map<String, Object?>> gaps = <Map<String, Object?>>[];
  for (int i = 1; i < numbers.length; i++) {
    final int step = numbers[i] - numbers[i - 1];
    if (step > 1) {
      gaps.add(<String, Object?>{
        'after': numbers[i - 1],
        'next': numbers[i],
        'missing': step - 1,
      });
    }
  }
  return gaps;
}

/// One block name's totals across a session.
///
/// [micros] is INCLUSIVE (a parent's span contains its children's) and is
/// kept only so a drill-down can show both; every ranking reads [selfMicros],
/// because ranking by the inclusive figure blames a parent for its child's
/// work.
final class PerfBlockTotal {
  PerfBlockTotal(this.name);

  final String name;

  /// Inclusive span time, summed over the session.
  int micros = 0;

  /// Exclusive span time, summed over the session.
  int selfMicros = 0;

  /// How many times the span ran, summed over the session.
  int count = 0;

  /// How many frames the span appeared in at least once. Separates a block
  /// that cost 10ms once from one that cost 0.1ms in each of a hundred frames;
  /// those need opposite fixes.
  int frames = 0;
}

/// Aggregates every frame's block map into one total per block name, in
/// first-seen order. Callers sort; this does not, so the two rankings can cut
/// from the same totals.
List<PerfBlockTotal> aggregateFrameBlocks(List<Map<String, Object?>> frames) {
  final Map<String, PerfBlockTotal> totals = <String, PerfBlockTotal>{};

  for (final Map<String, Object?> frame in frames) {
    for (final MapEntry<String, Map<String, Object?>> entry
        in blocksOfFrame(frame)) {
      final PerfBlockTotal total = totals.putIfAbsent(
        entry.key,
        () => PerfBlockTotal(entry.key),
      );
      total.micros += _int(entry.value['micros']);
      total.selfMicros += _int(entry.value['selfMicros']);
      total.count += _int(entry.value['count']);
      total.frames += 1;
    }
  }

  return totals.values.toList();
}

/// The [count] worst frames of [frames], ranked by the slower of their two
/// threads, each carrying its own top [blocksPerFrame] blocks by self time.
///
/// Compact on purpose: this feeds the drill-down, where one frame's full block
/// map (dozens of framework spans) would bury the handful that matter.
List<Map<String, Object?>> worstFrames(
  List<Map<String, Object?>> frames, {
  required int count,
  int blocksPerFrame = 5,
}) {
  final List<Map<String, Object?>> sorted =
      List<Map<String, Object?>>.from(frames)
        ..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              frameCostMicros(b).compareTo(frameCostMicros(a)),
        );

  return sorted.take(count).map((Map<String, Object?> frame) {
    final List<MapEntry<String, Map<String, Object?>>> blocks =
        blocksOfFrame(frame).toList()
          ..sort(
            (
              MapEntry<String, Map<String, Object?>> a,
              MapEntry<String, Map<String, Object?>> b,
            ) =>
                _int(b.value['selfMicros'])
                    .compareTo(_int(a.value['selfMicros'])),
          );
    return <String, Object?>{
      'frameNumber': frame['frameNumber'],
      'buildMs': microsToMs(_int(frame['buildMicros'])),
      'rasterMs': microsToMs(_int(frame['rasterMicros'])),
      'blocks': blocks
          .take(blocksPerFrame)
          .map(
            (MapEntry<String, Map<String, Object?>> e) => <String, Object?>{
              'name': e.key,
              'selfMs': microsToMs(_int(e.value['selfMicros'])),
              'count': _int(e.value['count']),
            },
          )
          .toList(),
    };
  }).toList();
}

/// The slower of a frame's build and raster time, in microseconds. The two
/// threads pipeline, so the slower one is what bounds the frame.
int frameCostMicros(Map<String, Object?> frame) {
  final int build = _int(frame['buildMicros']);
  final int raster = _int(frame['rasterMicros']);
  return build > raster ? build : raster;
}

/// The block entries of one frame whose values are actually maps.
Iterable<MapEntry<String, Map<String, Object?>>> blocksOfFrame(
  Map<String, Object?> frame,
) {
  final Object? blocks = frame['blocks'];
  if (blocks is! Map<String, Object?>) {
    return const <MapEntry<String, Map<String, Object?>>>[];
  }
  return blocks.entries
      .where((MapEntry<String, Object?> e) => e.value is Map<String, Object?>)
      .map(
        (MapEntry<String, Object?> e) => MapEntry<String, Map<String, Object?>>(
          e.key,
          e.value! as Map<String, Object?>,
        ),
      );
}

/// [micros] as milliseconds rounded to 0.01ms, the report's one time unit.
/// The rounding is part of what keeps a 3600-frame report inside its size
/// budget; nothing a fix follows from lives below 10 microseconds.
double microsToMs(int micros) => (micros / 10).round() / 100;

bool _overBudget(int micros) => micros > kFrameBudgetMicros;

/// p50 / p90 / p99 / worst of [micros], in milliseconds.
///
/// The index formula (`((n - 1) * p).round()`) is copied verbatim from
/// `frame_timing_summarizer.dart`'s `_findPercentile` so a reading here is
/// numerically comparable to Flutter's own, not just similarly named.
Map<String, Object?> _percentiles(List<int> micros) {
  final List<int> sorted = List<int>.from(micros)..sort();
  double at(double p) => sorted.isEmpty
      ? 0.0
      : microsToMs(sorted[((sorted.length - 1) * p).round()]);
  return <String, Object?>{
    'p50': at(0.50),
    'p90': at(0.90),
    'p99': at(0.99),
    'worst': sorted.isEmpty ? 0.0 : microsToMs(sorted.last),
  };
}

int _int(Object? value) => value is num ? value.toInt() : 0;
