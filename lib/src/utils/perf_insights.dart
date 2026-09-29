/// The LLM-first performance report: a bounded summary, ranked insights each
/// addressable by id, and the drill-down rows behind every insight.
///
/// The shape follows the precedents an agent already reads well:
/// chrome-devtools-mcp's insight set plus `performance_analyze_insight`
/// drill-down (Title / Summary / Detail / Estimated savings / Next step), and
/// Playwright trace's ordinal ids assigned BEFORE filtering, so an id stays
/// valid whatever the report cut.
///
/// Pure apart from reading [perfInsightContributors]: no binding access, so
/// `ext.dusk.perf_end` and magic_devtools' conformance test build the same
/// report from the same maps.
library;

import 'frame_summary.dart';
import 'perf_readers.dart';

/// What a measurement session switches on.
enum PerfMode {
  /// Build profiling on: blocks, self time and every counter. The
  /// instrumentation inflates per-type milliseconds, so rank by it, do not
  /// quote it.
  attribution,

  /// No `debugProfile*` flag touched: frame timings only, the pass whose
  /// milliseconds are worth comparing.
  timing;

  /// The mode named [name], or null when [name] names none.
  static PerfMode? tryParse(String name) => PerfMode.values.asNameMap()[name];
}

/// How much an insight should change what the reader does next. Severity is
/// kept apart from the measured value, as Lighthouse CI does, so a threshold
/// can move without the evidence changing.
enum PerfSeverity {
  info,
  warn,
  error;

  static PerfSeverity? tryParse(Object? name) =>
      name is String ? PerfSeverity.values.asNameMap()[name] : null;
}

/// Insights carried in the report; the rest stay reachable by id.
const int _kInsightLimit = 6;

/// Entries each counter map keeps in the report.
const int _kCounterListLimit = 3;

/// Route transitions kept in the report, slowest first.
const int _kRouteTransitionLimit = 3;

/// Frames a drill-down lists for one insight.
const int _kDetailFrameLimit = 10;

/// Frame-number gaps a drill-down lists.
const int _kDetailGapLimit = 20;

/// The shape of one ranked counter row. Positional rather than named, as in
/// chrome-devtools-mcp's packed call tree: eleven counter families at three
/// rows each are a third of the size budget with named keys, and the legend
/// ships in the payload so the rows stay self-describing.
const List<String> _kCounterColumns = <String>['name', 'count', 'perFrame'];

/// Counter keys that are sizes rather than counts: per frame means nothing.
const Set<String> _kGaugeKeys = <String>{'cacheSize'};

/// A frame is an over-budget PROBLEM once more than this share of painted
/// frames missed; below it the frames are named but ranked as a warning.
const double _kErrorShare = 0.1;

/// A block dominates once it owns this share of all self time...
const double _kDominantShare = 0.3;

/// ...and costs at least this much of its own time per painted frame, so a
/// session of three trivial blocks does not report one of them as dominant.
const double _kDominantMinMsPerFrame = 1.0;

/// A dominant block is an error once it alone eats half the frame budget.
const double _kDominantErrorMsPerFrame = kFrameBudgetMs / 2;

/// A block is a count outlier at this many runs per painted frame...
const double _kOutlierMinPerFrame = 20;

/// ...when that is also this many times the median block's rate.
const double _kOutlierMedianMultiple = 10;

/// The report plus the rows behind each of its insights.
final class PerfAnalysis {
  const PerfAnalysis._(this.report, this._drillDowns);

  /// The bounded report `ext.dusk.perf_end` returns.
  final Map<String, Object?> report;

  final Map<String, Map<String, Object?>> _drillDowns;

  /// Title / summary / detail / estimated savings / next step for insight
  /// [id], or null when this session never issued that id. Covers insights
  /// the report cut as well as the ones it carries.
  Map<String, Object?>? drillDown(String id) => _drillDowns[id];
}

/// Builds the bounded report for one closed session; see [analysePerf].
Map<String, Object?> buildPerfReport(
  Map<String, Object?> framePerf,
  Map<String, Object?> extras,
  Map<String, Object?>? wind, {
  required Map<String, Object?> env,
  PerfMode mode = PerfMode.attribution,
  int? framesDrawn,
  int framesOutsideSession = 0,
  bool sessionClockMismatch = false,
  double? durationMs,
  bool full = false,
}) =>
    analysePerf(
      framePerf,
      extras,
      wind,
      env: env,
      mode: mode,
      framesDrawn: framesDrawn,
      framesOutsideSession: framesOutsideSession,
      sessionClockMismatch: sessionClockMismatch,
      durationMs: durationMs,
      full: full,
    ).report;

/// Analyses one closed session into a report and its drill-downs.
///
/// [framePerf] is a `framePerfReader()` result, [extras] a
/// `perfExtrasReader()` result, [wind] `WindPerfResolver.stats()` or null
/// when no resolver is registered. [env] is carried through verbatim.
/// [framesDrawn] is the liveness counter's advance over the session and
/// defaults to the frames reported, which reads as complete coverage.
/// [framesOutsideSession] counts the frames the caller cut from [framePerf]
/// because they lay outside the session window, reported in `coverage` so a
/// cut is never silent. [sessionClockMismatch] says the caller could place no
/// frame in the window and kept them all, reported in `coverage` as
/// `sessionClockMismatch`. [durationMs] is the session's wall-clock length, null
/// when unknown.
/// [full] lifts every cut the report makes (block rankings, counter rows,
/// route transitions, insights), so every row is carried and `omitted` reads
/// all zeros: the unbounded form a runner writes to a file, never the one an
/// agent reads.
///
/// The report is `{mode, env, coverage, summary, counters, insights,
/// omitted}`. Every duration is in milliseconds and every count is given raw
/// and per painted frame, the one normalisation two sessions of different
/// length can be compared on. Nothing here throws on a malformed row, and a
/// throwing contributor becomes a `warn` insight.
PerfAnalysis analysePerf(
  Map<String, Object?> framePerf,
  Map<String, Object?> extras,
  Map<String, Object?>? wind, {
  required Map<String, Object?> env,
  PerfMode mode = PerfMode.attribution,
  int? framesDrawn,
  int framesOutsideSession = 0,
  bool sessionClockMismatch = false,
  double? durationMs,
  bool full = false,
}) {
  // 1. Frames and the timing summary every mode reports.
  final Object? rawFrames = framePerf['frames'];
  final List<Map<String, Object?>> frames = rawFrames is List<Object?>
      ? rawFrames.whereType<Map<String, Object?>>().toList()
      : const <Map<String, Object?>>[];
  final int painted = frames.length;
  final _Session session = _Session(
    mode: mode,
    frames: frames,
    painted: painted,
    drawn: framesDrawn ?? painted,
    outsideSession: framesOutsideSession,
    clockMismatch: sessionClockMismatch,
    full: full,
    frameSummary: summarizeFramePerf(frames),
    blocks: mode == PerfMode.attribution
        ? aggregateFrameBlocks(frames)
        : const <PerfBlockTotal>[],
  );
  final Map<String, Object?> omitted = <String, Object?>{};

  // 2. Rankings and counters, attribution only: timing mode leaves the
  //    profiling flags off, so there is nothing honest to rank.
  final Map<String, Object?> summary = <String, Object?>{
    'durationMs': durationMs == null ? null : _round(durationMs),
    'budgetMs': kFrameBudgetMs,
    'frames': session.frameSummary,
  };
  Map<String, Object?>? counters;
  if (mode == PerfMode.attribution) {
    summary['blocksBySelf'] = _rankBlocksBySelf(session, omitted);
    summary['blocksByCount'] = _rankBlocksByCount(session, omitted);
    summary['routeTransitions'] = _routeTransitions(
      extras,
      omitted,
      session.limit(_kRouteTransitionLimit),
    );
    counters = <String, Object?>{
      'columns': _kCounterColumns,
      // Null rather than a map of zeros: "wind never registered a perf
      // resolver" and "wind counted nothing" are different findings.
      'wind':
          wind == null ? null : _counterSection(wind, 'wind', session, omitted),
      'magic': _counterSection(extras, 'magic', session, omitted),
    };
  }

  // 3. Coverage: what the numbers above describe, and what they cannot.
  final Map<String, Object?> coverage = _coverage(session, wind);

  final Map<String, Object?> base = <String, Object?>{
    'mode': mode.name,
    'env': env,
    'coverage': coverage,
    'summary': summary,
    'counters': counters,
  };

  // 4. Insights: built-in rules first, then the host's contributors, each
  //    numbered as it is generated so the id survives the sort and the cut.
  final List<_Insight> insights = <_Insight>[
    ..._builtInInsights(session, coverage),
    ..._contributedInsights(<String, Object?>{
      ...base,
      'omitted': Map<String, Object?>.of(omitted),
    }),
  ];
  for (int i = 0; i < insights.length; i++) {
    insights[i].id = 'I${i + 1}';
  }
  final List<_Insight> ranked = List<_Insight>.of(insights)..sort(_byRank);
  final int? insightLimit = session.limit(_kInsightLimit);
  omitted['insights'] = _cut(ranked.length, insightLimit);

  return PerfAnalysis._(
    <String, Object?>{
      ...base,
      'insights': ranked
          .take(insightLimit ?? ranked.length)
          .map((_Insight i) => i.toReport())
          .toList(),
      'omitted': omitted,
    },
    <String, Map<String, Object?>>{
      for (final _Insight insight in insights)
        insight.id: insight.toDrillDown(),
    },
  );
}

// ---------------------------------------------------------------------------
// Session facts shared by the rules
// ---------------------------------------------------------------------------

final class _Session {
  _Session({
    required this.mode,
    required this.frames,
    required this.painted,
    required this.drawn,
    required this.outsideSession,
    required this.clockMismatch,
    required this.full,
    required this.frameSummary,
    required this.blocks,
  });

  final PerfMode mode;
  final List<Map<String, Object?>> frames;
  final int painted;
  final int drawn;

  /// Frames the caller cut for lying outside the session window.
  final int outsideSession;

  /// Whether the caller could not place any frame in the window and kept
  /// them all.
  final bool clockMismatch;

  /// Whether the report carries every row rather than the ranked head.
  final bool full;
  final Map<String, Object?> frameSummary;

  /// Every block total, UNCUT. Shares and medians are computed over this, not
  /// over a ranked head: a sum over a truncated list is a smaller number that
  /// looks like the same one.
  final List<PerfBlockTotal> blocks;

  late final List<PerfBlockTotal> bySelf = List<PerfBlockTotal>.of(blocks)
    ..sort(
      (PerfBlockTotal a, PerfBlockTotal b) =>
          _descThenName(a.selfMicros, b.selfMicros, a.name, b.name),
    );

  late final List<PerfBlockTotal> byCount = List<PerfBlockTotal>.of(blocks)
    ..sort(
      (PerfBlockTotal a, PerfBlockTotal b) =>
          _descThenName(a.count, b.count, a.name, b.name),
    );

  /// [value] per painted frame, null when nothing was painted.
  double? perFrame(num value) => painted == 0 ? null : _round(value / painted);

  /// The cut a ranked list takes, [bounded] in the default report and none
  /// in a [full] one.
  int? limit(int bounded) => full ? null : bounded;
}

// ---------------------------------------------------------------------------
// Summary sections
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _rankBlocksBySelf(
  _Session session,
  Map<String, Object?> omitted,
) {
  final int? limit = session.limit(kRankedBlockLimit);
  omitted['blocksBySelf'] = _cut(session.bySelf.length, limit);
  return session.bySelf
      .take(limit ?? session.bySelf.length)
      .map(
        (PerfBlockTotal b) => <String, Object?>{
          'name': b.name,
          'selfMs': microsToMs(b.selfMicros),
          'frames': b.frames,
        },
      )
      .toList();
}

List<Map<String, Object?>> _rankBlocksByCount(
  _Session session,
  Map<String, Object?> omitted,
) {
  final int? limit = session.limit(kRankedBlockLimit);
  omitted['blocksByCount'] = _cut(session.byCount.length, limit);
  return session.byCount
      .take(limit ?? session.byCount.length)
      .map(
        (PerfBlockTotal b) => <String, Object?>{
          'name': b.name,
          'count': b.count,
          'perFrame': session.perFrame(b.count),
        },
      )
      .toList();
}

/// The slowest route transitions, as `{route, ms}`, cut to [limit] when one
/// is given.
List<Map<String, Object?>> _routeTransitions(
  Map<String, Object?> extras,
  Map<String, Object?> omitted,
  int? limit,
) {
  final Object? raw = extras['routeTransitions'];
  final List<Map<String, Object?>> rows = raw is List<Object?>
      ? raw.whereType<Map<String, Object?>>().toList()
      : const <Map<String, Object?>>[];
  final List<Map<String, Object?>> transitions = rows
      .map(
        (Map<String, Object?> row) => <String, Object?>{
          'route': row['route'],
          'ms': microsToMs(_int(row['durationMicros'])),
        },
      )
      .toList()
    ..sort(
      (Map<String, Object?> a, Map<String, Object?> b) =>
          (b['ms']! as double).compareTo(a['ms']! as double),
    );
  omitted['routeTransitions'] = _cut(transitions.length, limit);
  return transitions.take(limit ?? transitions.length).toList();
}

/// One counter source (wind's stats, magic's extras) in report form.
///
/// A number becomes `{count, perFrame}` (a gauge stays bare), a
/// `Map<String, num>` becomes ranked `[name, count, perFrame]` rows
/// ([_kCounterColumns]) cut to [_kCounterListLimit] (uncut in a full report)
/// with the cut recorded as `omitted['<section>.<key>']`, and anything else is
/// left out rather than failing the report.
Map<String, Object?> _counterSection(
  Map<String, Object?> source,
  String section,
  _Session session,
  Map<String, Object?> omitted,
) {
  final double? Function(num value) perFrame = session.perFrame;
  final int? limit = session.limit(_kCounterListLimit);

  final Map<String, Object?> out = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in source.entries) {
    final Object? value = entry.value;
    if (value is num) {
      out[entry.key] = _kGaugeKeys.contains(entry.key)
          ? value
          : <String, Object?>{'count': value, 'perFrame': perFrame(value)};
      continue;
    }
    if (value is! Map<Object?, Object?>) continue;

    final List<MapEntry<String, num>> counts = <MapEntry<String, num>>[
      for (final MapEntry<Object?, Object?> e in value.entries)
        if (e.value is num) MapEntry<String, num>('${e.key}', e.value! as num),
    ]..sort(
        (MapEntry<String, num> a, MapEntry<String, num> b) =>
            _descThenName(a.value, b.value, a.key, b.key),
      );
    omitted['$section.${entry.key}'] = _cut(counts.length, limit);
    out[entry.key] = counts
        .take(limit ?? counts.length)
        .map(
          (MapEntry<String, num> e) => <Object?>[
            e.key,
            e.value,
            perFrame(e.value),
          ],
        )
        .toList();
  }
  return out;
}

/// Whether the summary describes every frame the engine drew, and which
/// sources it could not read.
///
/// `framesDrawn` comes from the liveness counter, which a post-frame callback
/// increments and cannot miss; `framesSummarized` counts the records Flutter's
/// `onReportTimings` delivered, and Flutter batches those, so a session that
/// ends shortly after the work can close before the last timings arrive.
/// Measured on Chrome: a theme toggle drew 4 frames, 2 were reported, and the
/// report looked complete. The prose explaining a gap lives in the coverage
/// insight, not here, so the report does not carry it twice.
///
/// `framesOutsideSession` is the other direction: reported frames that were
/// NOT counted because they belong to no part of the window (drawn before
/// `perf_begin` and delivered late, or the idle frame `perf_end` draws to
/// flush the tail). Without it a session that drew 24 frames and summarized
/// 24 gives no hint that 7 more were read and dropped. `sessionClockMismatch`,
/// present only when true, says no frame could be placed in the window, so
/// nothing was cut and the summary may include frames from either side of it.
Map<String, Object?> _coverage(_Session session, Map<String, Object?>? wind) {
  final List<String> missing = <String>[
    if (session.mode == PerfMode.attribution) ...<String>[
      if (wind == null) 'wind',
      if (session.painted > 0 && session.blocks.isEmpty) 'blocks',
      if (session.blocks.isNotEmpty &&
          session.blocks.every((PerfBlockTotal b) => b.selfMicros == 0) &&
          session.blocks.any((PerfBlockTotal b) => b.micros > 0))
        'blockSelfTime',
    ],
  ];
  // Kept-all frames include ones from either side of the window, so a
  // mismatch is never a complete account of the session however many
  // arrived.
  final bool complete =
      !session.clockMismatch && session.painted >= session.drawn;
  return <String, Object?>{
    'framesDrawn': session.drawn,
    'framesSummarized': session.painted,
    'framesOutsideSession': session.outsideSession,
    if (session.clockMismatch) 'sessionClockMismatch': true,
    'complete': complete,
    'missing': missing,
  };
}

// ---------------------------------------------------------------------------
// Built-in rules
// ---------------------------------------------------------------------------

List<_Insight> _builtInInsights(
  _Session session,
  Map<String, Object?> coverage,
) =>
    <_Insight?>[
      _overBudgetInsight(session),
      _droppedFramesInsight(session),
      if (session.mode == PerfMode.attribution) ...<_Insight?>[
        _dominantBlockInsight(session),
        _countOutlierInsight(session),
      ],
      _coverageInsight(session, coverage),
    ].whereType<_Insight>().toList();

/// Frames whose slower thread exceeded [kFrameBudgetMs].
_Insight? _overBudgetInsight(_Session session) {
  final List<Map<String, Object?>> over = session.frames
      .where(
          (Map<String, Object?> f) => frameCostMicros(f) > kFrameBudgetMicros)
      .toList();
  if (over.isEmpty) return null;

  final int excessMicros = over.fold<int>(
    0,
    (int sum, Map<String, Object?> f) =>
        sum + frameCostMicros(f) - kFrameBudgetMicros,
  );
  final int onBuild = session.frameSummary['overBudgetBuild']! as int;
  final int onRaster = session.frameSummary['overBudgetRaster']! as int;
  final double share = over.length / session.painted;
  final String count = '${over.length} of ${session.painted}';

  return _Insight(
    severity: share > _kErrorShare ? PerfSeverity.error : PerfSeverity.warn,
    title: '$count frames over the ${kFrameBudgetMs}ms budget',
    summary: '$count painted frames took longer than ${kFrameBudgetMs}ms on '
        'their slower thread ($onBuild over on build, $onRaster on raster). '
        'Their time past the budget totals ${microsToMs(excessMicros)}ms, '
        'the most a fix to these frames alone could win back.',
    evidence: _evidence(
      metric: 'framesOverBudget',
      value: over.length,
      perFrame: session.perFrame(over.length),
      threshold: <String, Object?>{
        'budgetMs': kFrameBudgetMs,
        'errorShare': _kErrorShare,
      },
    ),
    savingsMs: microsToMs(excessMicros),
    nextStep: onBuild >= onRaster
        ? 'Build-bound: drill in for the worst frames and their self-time '
            'blocks.'
        : 'Raster-bound: look at what these frames paint (clips, opacity, '
            'shadows, images), not at builds.',
    detail: <String, Object?>{
      'overBudgetBuild': onBuild,
      'overBudgetRaster': onRaster,
      'worstFrames': worstFrames(over, count: _kDetailFrameLimit),
    },
  );
}

/// Frames missing from the `frameNumber` sequence.
_Insight? _droppedFramesInsight(_Session session) {
  final List<Map<String, Object?>> gaps = frameGaps(session.frames);
  if (gaps.isEmpty) return null;

  final int dropped = session.frameSummary['dropped']! as int;
  final double share = dropped / (session.painted + dropped);

  return _Insight(
    severity: share > _kErrorShare ? PerfSeverity.error : PerfSeverity.warn,
    title: '$dropped frames dropped in ${gaps.length} gaps',
    summary: 'The frameNumber sequence skips $dropped numbers across '
        '${gaps.length} gaps: frames the engine numbered and never reported '
        'timings for, which is how a dropped scene shows on web.',
    evidence: _evidence(
      metric: 'framesDropped',
      value: dropped,
      perFrame: session.perFrame(dropped),
      threshold: <String, Object?>{
        'minGap': 2,
        'errorShare': _kErrorShare,
      },
    ),
    nextStep: 'Drill in for the gaps; one right after a long frame is that '
        'frame\'s cost, not a second problem.',
    detail: <String, Object?>{
      'gaps': gaps.take(_kDetailGapLimit).toList(),
      'gapsOmitted': _cut(gaps.length, _kDetailGapLimit),
    },
  );
}

/// One block owning a large share of all self time.
_Insight? _dominantBlockInsight(_Session session) {
  final int totalSelf = session.blocks.fold<int>(
    0,
    (int sum, PerfBlockTotal b) => sum + b.selfMicros,
  );
  if (totalSelf == 0 || session.painted == 0) return null;

  final PerfBlockTotal top = session.bySelf.first;
  final double share = top.selfMicros / totalSelf;
  final double msPerFrame = top.selfMicros / 1000 / session.painted;
  if (share < _kDominantShare || msPerFrame < _kDominantMinMsPerFrame) {
    return null;
  }
  final int percent = (share * 100).round();

  return _Insight(
    severity: msPerFrame > _kDominantErrorMsPerFrame
        ? PerfSeverity.error
        : PerfSeverity.warn,
    title: '${top.name} owns $percent% of self time',
    summary: '${top.name} ran ${top.count} times in ${top.frames} of '
        '${session.painted} painted frames and spent '
        '${microsToMs(top.selfMicros)}ms of its own time, children excluded: '
        '$percent% of all self time in the session. Build profiling inflates '
        'the milliseconds, so trust the share over the absolute figure.',
    evidence: _evidence(
      metric: 'blockSelfMs',
      value: microsToMs(top.selfMicros),
      perFrame: _round(msPerFrame),
      threshold: <String, Object?>{
        'minShare': _kDominantShare,
        'minMsPerFrame': _kDominantMinMsPerFrame,
        'errorMsPerFrame': _kDominantErrorMsPerFrame,
      },
    ),
    savingsMs: microsToMs(top.selfMicros),
    nextStep: 'Find why ${top.name} rebuilds or what its build does; confirm '
        'any fix with mode=timing.',
    detail: <String, Object?>{
      'block': <String, Object?>{
        'name': top.name,
        'selfMs': microsToMs(top.selfMicros),
        'inclusiveMs': microsToMs(top.micros),
        'count': top.count,
        'frames': top.frames,
        'share': _round(share),
      },
      'totalSelfMs': microsToMs(totalSelf),
      'frames': _framesFor(session, top.name, 'selfMicros'),
    },
  );
}

/// One block running far more often per frame than the rest.
_Insight? _countOutlierInsight(_Session session) {
  if (session.blocks.isEmpty || session.painted == 0) return null;

  final PerfBlockTotal top = session.byCount.first;
  final double perFrame = top.count / session.painted;
  final List<double> rates = session.blocks
      .map((PerfBlockTotal b) => b.count / session.painted)
      .toList()
    ..sort();
  final double median = rates[rates.length ~/ 2];
  if (perFrame < _kOutlierMinPerFrame ||
      perFrame < _kOutlierMedianMultiple * median) {
    return null;
  }

  return _Insight(
    severity: PerfSeverity.warn,
    title: '${top.name} runs ${_round(perFrame)} times per painted frame',
    summary: '${top.name} ran ${top.count} times over ${session.painted} '
        'painted frames, ${_round(perFrame)} per frame against a median block '
        'rate of ${_round(median)}. A count this far above the rest usually '
        'means every row of a list rebuilding, or a listener firing per item.',
    evidence: _evidence(
      metric: 'blockCountPerFrame',
      value: top.count,
      perFrame: _round(perFrame),
      threshold: <String, Object?>{
        'minPerFrame': _kOutlierMinPerFrame,
        'minMedianMultiple': _kOutlierMedianMultiple,
      },
    ),
    nextStep:
        'Check whether ${top.name} rebuilds with unchanged inputs (const, '
        'keys, narrower listeners).',
    detail: <String, Object?>{
      'block': <String, Object?>{
        'name': top.name,
        'count': top.count,
        'perFrame': _round(perFrame),
        'frames': top.frames,
        'selfMs': microsToMs(top.selfMicros),
      },
      'medianPerFrame': _round(median),
      'frames': _framesFor(session, top.name, 'count'),
    },
  );
}

/// Frames the engine drew and never reported, or sources never read.
_Insight? _coverageInsight(_Session session, Map<String, Object?> coverage) {
  // Outranks the rest: every other figure in the report sits on frames that
  // may not belong to the session.
  if (session.clockMismatch) {
    return _Insight(
      severity: PerfSeverity.warn,
      title: 'No frame could be placed in the session window',
      summary: 'Frames carried vsync timestamps and none fell between '
          'perf_begin and perf_end, so the engine clock and '
          'FlutterTimeline.now disagree on this device. Every frame read was '
          'kept, including ones drawn before the session and the flush frame, '
          'so the summary may describe more than this session.',
      evidence: _evidence(
        metric: 'sessionClockMismatch',
        value: session.painted,
        perFrame: null,
        threshold: <String, Object?>{'minPlaced': 1},
      ),
      nextStep: 'Treat this unit as unmeasured; dusk:perf_run leaves it out '
          'of the series medians.',
      detail: coverage,
    );
  }

  final int unreported = session.drawn - session.painted;
  final List<String> missing = coverage['missing']! as List<String>;
  if (unreported <= 0 && missing.isEmpty) return null;

  final bool degraded = unreported > 0 ||
      missing.contains('blocks') ||
      missing.contains('blockSelfTime');

  return _Insight(
    severity: degraded ? PerfSeverity.warn : PerfSeverity.info,
    title: unreported > 0
        ? 'Timings arrived for ${session.painted} of ${session.drawn} frames'
        : 'Not measured: ${missing.join(', ')}',
    summary: <String>[
      if (unreported > 0)
        'Timings arrived for ${session.painted} of ${session.drawn} drawn '
            'frames, so the summary describes a subset of this session. The '
            'missing frames may be the expensive ones: read a thin ranking as '
            '"not reported", not as "nothing was slow".',
      if (missing.contains('wind'))
        'No wind perf resolver was registered, so counters.wind is null, '
            'which is not the same finding as zero.',
      if (missing.contains('blocks'))
        'No frame carried a block map although build profiling was on: the '
            'host\'s frame watcher is not draining the timeline.',
      if (missing.contains('blockSelfTime'))
        'Blocks carry no selfMicros, so the self-time ranking reads zero: the '
            'host\'s telescope predates exclusive block time.',
    ].join(' '),
    // Two findings, two metrics: frames that never reported, or sources that
    // were never read. A frame metric reading 0 would say the first is fine
    // while the insight is about the second.
    evidence: unreported > 0
        ? _evidence(
            metric: 'framesUnreported',
            value: unreported,
            perFrame: session.perFrame(unreported),
            threshold: <String, Object?>{'minReportedShare': 1.0},
          )
        : _evidence(
            metric: 'sourcesMissing',
            value: missing.length,
            perFrame: null,
            threshold: <String, Object?>{'maxMissing': 0},
          ),
    nextStep: unreported > 0
        ? 'Settle longer before perf_end, then rerun.'
        : 'Wire the missing source (MagicPerfIntegration), then rerun.',
    detail: coverage,
  );
}

/// The frames where block [name] weighed most on [key], compact.
List<Map<String, Object?>> _framesFor(
  _Session session,
  String name,
  String key,
) {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (final Map<String, Object?> frame in session.frames) {
    final Object? blocks = frame['blocks'];
    final Object? block = blocks is Map<String, Object?> ? blocks[name] : null;
    if (block is! Map<String, Object?>) continue;
    rows.add(<String, Object?>{
      'frameNumber': frame['frameNumber'],
      'selfMs': microsToMs(_int(block['selfMicros'])),
      'count': _int(block['count']),
      'buildMs': microsToMs(_int(frame['buildMicros'])),
      '_rank': _int(block[key]),
    });
  }
  rows.sort(
    (Map<String, Object?> a, Map<String, Object?> b) =>
        (b['_rank']! as int).compareTo(a['_rank']! as int),
  );
  return rows
      .take(_kDetailFrameLimit)
      .map((Map<String, Object?> row) => row..remove('_rank'))
      .toList();
}

// ---------------------------------------------------------------------------
// Contributors
// ---------------------------------------------------------------------------

/// Runs every host contributor against [report], converting each insight it
/// returns, and turning a throw or a malformed insight into one `warn`
/// insight naming the contributor.
///
/// Deliberately handled, not swallowed: the contributors are assigned in
/// another repository, a throw here would cost the whole report the built-in
/// rules already produced, and the failure is reported IN that report, where
/// the reader will see it.
List<_Insight> _contributedInsights(Map<String, Object?> report) {
  final List<_Insight> out = <_Insight>[];
  for (int k = 0; k < perfInsightContributors.length; k++) {
    final int number = k + 1;
    final List<_Insight> converted = <_Insight>[];
    try {
      for (final Map<String, Object?> raw
          in perfInsightContributors[k](report)) {
        final String? problem = _malformation(raw);
        if (problem != null) {
          converted
            ..clear()
            ..add(_contributorFailure(number, 'returned $problem'));
          break;
        }
        converted.add(_Insight.fromContributor(raw));
      }
    } catch (e) {
      converted
        ..clear()
        ..add(_contributorFailure(number, 'threw ${e.runtimeType}: $e'));
    }
    out.addAll(converted);
  }
  return out;
}

/// What is wrong with a contributed insight, or null when nothing is.
String? _malformation(Map<String, Object?> raw) {
  final List<String> missing = <String>[
    if (PerfSeverity.tryParse(raw['severity']) == null) 'severity',
    if (raw['title'] is! String) 'title',
    if (raw['nextStep'] is! String) 'nextStep',
    if (!_isEvidence(raw['evidence'])) 'evidence',
  ];
  return missing.isEmpty
      ? null
      : 'an insight missing or mistyping ${missing.join(', ')}';
}

bool _isEvidence(Object? value) =>
    value is Map<String, Object?> &&
    <String>['metric', 'value', 'perFrame', 'threshold']
        .every(value.containsKey);

_Insight _contributorFailure(int number, String what) => _Insight(
      severity: PerfSeverity.warn,
      title: 'Insight contributor #$number failed',
      summary: 'Contributor #$number $what. Its insights are missing from '
          'this report; the built-in insights are unaffected.',
      evidence: _evidence(
        metric: 'contributorErrors',
        value: 1,
        perFrame: null,
        threshold: null,
      ),
      nextStep: 'Fix contributor #$number in the host (magic_devtools), then '
          'rerun the session.',
      detail: <String, Object?>{
        'contributor': number,
        'error': what,
      },
    );

// ---------------------------------------------------------------------------
// The insight record
// ---------------------------------------------------------------------------

final class _Insight {
  _Insight({
    required this.severity,
    required this.title,
    required this.summary,
    required this.evidence,
    required this.nextStep,
    this.savingsMs,
    this.detail,
  });

  factory _Insight.fromContributor(Map<String, Object?> raw) {
    final Object? savings = raw['estimatedSavingsMs'];
    final Object? summary = raw['summary'];
    return _Insight(
      severity: PerfSeverity.tryParse(raw['severity'])!,
      title: raw['title']! as String,
      summary: summary is String ? summary : raw['title']! as String,
      evidence: raw['evidence']! as Map<String, Object?>,
      nextStep: raw['nextStep']! as String,
      savingsMs: savings is num ? savings.toDouble() : null,
      detail: raw['detail'] ?? raw['evidence'],
    );
  }

  /// Assigned by the engine in generation order.
  String id = '';
  final PerfSeverity severity;
  final String title;
  final String summary;
  final Map<String, Object?> evidence;
  final String nextStep;
  final double? savingsMs;
  final Object? detail;

  Map<String, Object?> toReport() => <String, Object?>{
        'id': id,
        'severity': severity.name,
        'title': title,
        'evidence': evidence,
        if (savingsMs != null) 'estimatedSavingsMs': savingsMs,
        'nextStep': nextStep,
      };

  Map<String, Object?> toDrillDown() => <String, Object?>{
        'id': id,
        'severity': severity.name,
        'title': title,
        'summary': summary,
        'detail': detail ?? evidence,
        'estimatedSavingsMs': savingsMs,
        'nextStep': nextStep,
      };
}

/// Severity first, then the larger saving, then generation order.
int _byRank(_Insight a, _Insight b) {
  final int bySeverity = b.severity.index.compareTo(a.severity.index);
  if (bySeverity != 0) return bySeverity;
  final int bySavings = (b.savingsMs ?? 0).compareTo(a.savingsMs ?? 0);
  if (bySavings != 0) return bySavings;
  return _ordinal(a.id).compareTo(_ordinal(b.id));
}

Map<String, Object?> _evidence({
  required String metric,
  required num value,
  required double? perFrame,
  required Map<String, Object?>? threshold,
}) =>
    <String, Object?>{
      'metric': metric,
      'value': value,
      'perFrame': perFrame,
      'threshold': threshold,
    };

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

int _descThenName(num a, num b, String aName, String bName) {
  final int byValue = b.compareTo(a);
  return byValue != 0 ? byValue : aName.compareTo(bName);
}

/// Rows a list of [length] loses to [limit]; none when there is no limit.
int _cut(int length, int? limit) =>
    limit != null && length > limit ? length - limit : 0;

int _ordinal(String id) => int.parse(id.substring(1));

double _round(num value) => (value * 100).round() / 100;

int _int(Object? value) => value is num ? value.toInt() : 0;
