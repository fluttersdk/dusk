/// Turns a list of per-frame performance records into the summary an agent
/// can act on: percentile/worst/budget-violation metrics using Flutter's own
/// metric names, plus a dropped-frame count and the worst-N offenders.
///
/// This is a pure function with no binding access, so it is trivially
/// testable: it never reads `SchedulerBinding` or any other binding.
///
/// [frames] must be `List<Map<String, Object?>>` shaped exactly like
/// `FramePerfRecord.toJson()` (telescope repo): `frameNumber`, `buildMicros`,
/// `rasterMicros`, `vsyncOverheadMicros`, `totalSpanMicros`, `time`, `blocks`.
/// dusk cannot import telescope's record type (frozen contract #10), so the
/// input is the plain map shape rather than the typed record.
library;

/// `kBuildBudget` from `flutter_driver`'s `timeline_summary.dart:42`, in
/// microseconds so it can be compared against the raw `buildMicros` /
/// `rasterMicros` fields without a conversion at every call site.
const int _kFrameBuildBudgetMicros = 16000;

/// Summarizes [frames] into the metric-name-keyed map an agent reads.
///
/// Every "*_time_millis" and "*_budget_count" key below matches
/// `flutter_driver`'s `TimelineSummary.summaryJson` (`timeline_summary.dart:
/// 285-303`) character for character, so a reading here is comparable to
/// `flutter_driver`'s and to devicelab's. `dropped_frame_count` and
/// `worst_frames` have no Flutter-summarizer counterpart; they are added
/// because a dropped scene on web is a missing `frameNumber` rather than a
/// slow frame, and the ranked worst offenders (with block attribution) are
/// what actually direct a fix.
///
/// [worstFrameCount] bounds how many entries `worst_frames` carries, ranked
/// by `buildMicros` descending (the axis an app author can act on).
///
/// An empty [frames] list returns zeros throughout rather than throwing or
/// dividing by zero; that is the case a real run hits first, when the
/// operator ends a session that never started.
Map<String, Object?> summarizeFramePerf(
  List<Map<String, Object?>> frames, {
  int worstFrameCount = 5,
}) {
  final List<int> buildMicros = frames
      .map((Map<String, Object?> f) => _micros(f['buildMicros']))
      .toList();
  final List<int> rasterMicros = frames
      .map((Map<String, Object?> f) => _micros(f['rasterMicros']))
      .toList();
  // Dropped ENTRIES, not zeroed ones. `buildMicros` and `rasterMicros` degrade
  // gracefully at 0, because a missing duration reads as a frame that cost
  // nothing. A sequence POSITION does not: `_droppedFrameCount` derives its
  // answer from gaps between consecutive numbers, so substituting 0 for a
  // missing frame number manufactures a gap the size of the number before it.
  // One malformed row mid-session reported 101 drops against a truth of 1,
  // and that is the metric an agent reads to decide whether the app is janky.
  // A row with no usable position simply leaves the sequence.
  final List<int> frameNumbers = frames
      .map((Map<String, Object?> f) => f['frameNumber'])
      .whereType<num>()
      .map((num n) => n.toInt())
      .toList();

  final List<int> sortedBuildMicros = List<int>.from(buildMicros)..sort();
  final List<int> sortedRasterMicros = List<int>.from(rasterMicros)..sort();

  final double averageBuildMillis = _averageMillis(buildMicros);
  final double averageRasterMillis = _averageMillis(rasterMicros);

  return <String, Object?>{
    'average_frame_build_time_millis': averageBuildMillis,
    '90th_percentile_frame_build_time_millis':
        _percentileMillis(sortedBuildMicros, 0.90),
    '99th_percentile_frame_build_time_millis':
        _percentileMillis(sortedBuildMicros, 0.99),
    'worst_frame_build_time_millis': _worstMillis(sortedBuildMicros),
    'missed_frame_build_budget_count': _missedBudgetCount(buildMicros),
    'average_frame_rasterizer_time_millis': averageRasterMillis,
    'stddev_frame_rasterizer_time_millis': _meanAbsoluteDeviationMillis(
      rasterMicros,
      averageRasterMillis,
    ),
    '90th_percentile_frame_rasterizer_time_millis':
        _percentileMillis(sortedRasterMicros, 0.90),
    '99th_percentile_frame_rasterizer_time_millis':
        _percentileMillis(sortedRasterMicros, 0.99),
    'worst_frame_rasterizer_time_millis': _worstMillis(sortedRasterMicros),
    'missed_frame_rasterizer_budget_count': _missedBudgetCount(rasterMicros),
    'frame_count': frames.length,
    'frame_rasterizer_count': frames.length,
    'dropped_frame_count': _droppedFrameCount(frameNumbers),
    'worst_frames': _worstFrames(frames, worstFrameCount),
  };
}

/// Average of [micros] in milliseconds. Returns 0.0 for an empty list rather
/// than dividing by zero.
/// Reads one numeric field out of a frame map.
///
/// Tolerant on purpose, and for a reason this file cannot see from the inside:
/// these maps are built in another repository and arrive over a function
/// pointer, so a renamed or absent key does not fail to compile. An `as num`
/// cast on a missing key throws a TypeError that `perf_end` turns into an
/// opaque error envelope, which costs the WHOLE report rather than the one row
/// that was malformed. The callers on the other side of this boundary already
/// take the tolerant posture: `_readFrames` skips non-map entries rather than
/// crashing the report they are one row of.
int _micros(Object? value) => value is num ? value.toInt() : 0;

double _averageMillis(List<int> micros) {
  if (micros.isEmpty) return 0.0;
  final int sum = micros.reduce((int a, int b) => a + b);
  return (sum / micros.length) / 1000.0;
}

/// The 100*[p]-th percentile of [sortedMicros], in milliseconds.
///
/// [sortedMicros] must already be sorted ascending. The index formula
/// (`((n - 1) * p).round()`) is copied verbatim from
/// `frame_timing_summarizer.dart`'s `_findPercentile` so a reading here is
/// numerically comparable to Flutter's own, not just similarly named.
double _percentileMillis(List<int> sortedMicros, double p) {
  if (sortedMicros.isEmpty) return 0.0;
  final int index = ((sortedMicros.length - 1) * p).round();
  return sortedMicros[index] / 1000.0;
}

/// The largest value in [sortedMicros], in milliseconds. 0.0 when empty.
double _worstMillis(List<int> sortedMicros) {
  if (sortedMicros.isEmpty) return 0.0;
  return sortedMicros.last / 1000.0;
}

/// Count of [micros] entries that STRICTLY exceed the 16ms build budget,
/// mirroring `_countExceed`'s `>` comparison (an exact-budget frame does not
/// count as missed).
int _missedBudgetCount(List<int> micros) {
  int count = 0;
  for (final int m in micros) {
    if (m > _kFrameBuildBudgetMicros) count++;
  }
  return count;
}

/// Mean absolute deviation of [micros] from [averageMillis], in
/// milliseconds. This mirrors `timeline_summary.dart`'s
/// `computeStandardDeviationFrameRasterizerTimeMillis` exactly (it is a mean
/// absolute deviation, not a textbook standard deviation); the name is kept
/// as `stddev_*` because that is the wire string Flutter itself emits.
double _meanAbsoluteDeviationMillis(List<int> micros, double averageMillis) {
  if (micros.isEmpty) return 0.0;
  double tally = 0.0;
  for (final int m in micros) {
    tally += (averageMillis - (m / 1000.0)).abs();
  }
  return tally / micros.length;
}

/// Counts frames dropped from the sequence, derived from GAPS between
/// consecutive [frameNumbers]: on web a dropped scene is a missing frame
/// number rather than a slow one.
///
/// A gap of more than 1 between consecutive entries contributes `gap - 1`
/// dropped frames. A non-monotonic or duplicated pair (gap <= 1, including 0
/// or negative) contributes nothing; the count never goes negative. Empty
/// and single-element lists have no adjacent pair to compare, so they
/// report 0.
int _droppedFrameCount(List<int> frameNumbers) {
  if (frameNumbers.length < 2) return 0;

  int dropped = 0;
  for (int i = 1; i < frameNumbers.length; i++) {
    final int gap = frameNumbers[i] - frameNumbers[i - 1];
    if (gap > 1) {
      dropped += gap - 1;
    }
  }
  return dropped;
}

/// The worst [count] frames from [frames], ranked by `buildMicros`
/// descending, each carrying its original block attribution untouched.
List<Map<String, Object?>> _worstFrames(
  List<Map<String, Object?>> frames,
  int count,
) {
  final List<Map<String, Object?>> sorted =
      List<Map<String, Object?>>.from(frames)
        ..sort((Map<String, Object?> a, Map<String, Object?> b) {
          final int aBuild = _micros(a['buildMicros']);
          final int bBuild = _micros(b['buildMicros']);
          return bBuild.compareTo(aBuild);
        });
  return sorted.take(count).toList();
}
