import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

import '../perf/scenario.dart';
import 'json_output.dart';

/// Rows the human table prints before pointing at `--json` for the rest.
const int _kTableRowLimit = 20;

/// Per-frame metrics where a rise is the good outcome, not the bad one.
///
/// Every other metric is gated as higher-is-worse: a `blocks.*` build count,
/// a wrapper emission, an inherited-widget read all cost more work as they
/// grow. A cache hit is the opposite: it is work the run avoided, so a rise
/// reads as an improvement (or informational) and a fall is what regresses.
/// Extend this set when a new counter with the same "more is good" shape
/// ships (`dusk_perf_run_command.dart:440-457` lists every `wind.*`/`magic.*`
/// key `dusk:perf_run` can emit).
const Set<String> _kHigherIsBetterMetrics = <String>{
  'wind.cacheHits',
};

/// `artisan dusk:perf_compare <a.json> <b.json> [--json]`: judge run B
/// against run A, both written by `dusk:perf_run`.
///
/// Counts per painted frame are the gate. A run that drew 10% fewer frames
/// reports 10% fewer of every raw count, which reads as an improvement and is
/// not one, so raw counts are never compared. Milliseconds are gated only from
/// the timing-mode medians (`--timing`), since attribution profiling inflates
/// every duration; raster milliseconds from an emulator are reported as info
/// and never gated. Exits 1 on an error-level regression.
class DuskPerfCompareCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:perf_compare';

  @override
  String get description =>
      'Compare two dusk:perf_run files on counts per painted frame (and '
      'timing-mode ms) and print a verdict table.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser
      ..addOption('a', help: 'The baseline run file (or the first argument).')
      ..addOption('b',
          help: 'The candidate run file (or the second argument).');
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Both paths, positional or named: MCP passes names.
    final String? pathA =
        ctx.input.argument(0) ?? ctx.input.option('a') as String?;
    final String? pathB =
        ctx.input.argument(1) ?? ctx.input.option('b') as String?;
    if (pathA == null || pathB == null) {
      ctx.output.error(
        'Usage: dusk:perf_compare <a.json> <b.json>: two files written by '
        'dusk:perf_run, the baseline first.',
      );
      return 1;
    }

    // 2. Read and judge. A bad file is the caller's input, so it is reported
    //    rather than thrown.
    final Map<String, Object?> result;
    try {
      result = comparePerfRuns(await _read(pathA), await _read(pathB));
    } on FormatException catch (e) {
      ctx.output.error(e.message);
      return 1;
    } on FileSystemException catch (e) {
      ctx.output.error('Cannot read ${e.path}: ${e.message}');
      return 1;
    }

    // 3. Report.
    emitEnvelope(ctx, result, () => _printTable(ctx, result));
    return _hasErrorRegression(result) ? 1 : 0;
  }
}

/// Judges run [b] against run [a], both `dusk:perf_run` files.
///
/// Returns:
/// ```json
/// {
///   "verdict": "regressed",          // unchanged | improved | regressed
///   "thresholds": {"warn": 10, "error": 25},
///   "frames": {"painted": {"a": 100, "b": 90}},
///   "rows": [{"metric": "blocks.MonitorRow", "a": 2.0, "b": 2.6,
///             "deltaPct": 30.0, "verdict": "regressed", "severity": "error"}],
///   "unchanged": 41,
///   "timing": {"gated": false, "note": "..."}
/// }
/// ```
///
/// Every metric is counts per painted frame from the attribution medians, or
/// `timing.*` milliseconds from the timing medians, and almost all of them
/// are higher-is-worse. The exception is [_kHigherIsBetterMetrics] (a cache
/// hit and any counter shaped like one): work the run avoided, so a rise
/// there is an improvement, never a regression. A change is judged against
/// [PerfThresholds] from B's scenario (else A's, else 10/25 percent) and is
/// `unchanged` whenever it stays inside the repeat-to-repeat range either run
/// recorded for that metric: a delta the repeats themselves produce is
/// noise, not a finding. A metric A never recorded is a warn-level
/// `regressed` with no percentage (`improved` instead when the metric is
/// higher-is-better). `rows` lists every judged change and every info row
/// (including a scenario or environment change between the two runs);
/// `unchanged` counts the rest.
///
/// Throws [FormatException] when either run has no measured repeat.
Map<String, Object?> comparePerfRuns(
  Map<String, Object?> a,
  Map<String, Object?> b,
) {
  // 1. Both runs must carry a measurement.
  final Map<String, Object?> summaryA = _measuredSummary(a, 'A');
  final Map<String, Object?> summaryB = _measuredSummary(b, 'B');
  final PerfThresholds thresholds = PerfThresholds.fromJson(
    _scenario(b)['thresholds'] ?? _scenario(a)['thresholds'],
  );

  // 2. Counts per painted frame, the primary gate.
  final List<_Row> rows = _judge(
    _numbers(summaryA['perFrame']),
    _numbers(summaryB['perFrame']),
    noiseA: _noise(summaryA, 'perFrame'),
    noiseB: _noise(summaryB, 'perFrame'),
    thresholds: thresholds,
    higherIsBetter: (String metric) => _kHigherIsBetterMetrics.contains(metric),
  );

  // 3. Milliseconds, from timing medians only.
  final Map<String, Object?>? timingA = _timing(summaryA);
  final Map<String, Object?>? timingB = _timing(summaryB);
  final bool timed = timingA != null && timingB != null;
  if (timed) {
    final bool emulator = _emulator(a) || _emulator(b);
    rows.addAll(
      _judge(
        _numbers(timingA['ms']),
        _numbers(timingB['ms']),
        noiseA: _noise(timingA, 'ms'),
        noiseB: _noise(timingB, 'ms'),
        thresholds: thresholds,
        prefix: 'timing.',
        infoOnly: (String metric) => emulator && metric.startsWith('rasterMs'),
      ),
    );
  }

  // 4. Info rows for a context change: a metric delta means something
  //    different when the scenario or the environment moved underneath it.
  rows.addAll(
    <_Row?>[
      _contextRow('scenario.name', _scenario(a)['name'], _scenario(b)['name']),
      _contextRow('env.target', _env(a)['target'], _env(b)['target']),
      _contextRow('env.buildMode', _env(a)['buildMode'], _env(b)['buildMode']),
    ].whereType<_Row>(),
  );

  // 5. The verdict reads gated rows only.
  final List<_Row> gated = rows.where((_Row r) => !r.info).toList();
  final String verdict = gated.any((_Row r) => r.verdict == _Verdict.regressed)
      ? _Verdict.regressed.name
      : gated.any((_Row r) => r.verdict == _Verdict.improved)
          ? _Verdict.improved.name
          : _Verdict.unchanged.name;
  final List<_Row> listed = rows
      .where((_Row r) => r.info || r.verdict != _Verdict.unchanged)
      .toList()
    ..sort(_Row.byWeight);

  return <String, Object?>{
    'verdict': verdict,
    'thresholds': thresholds.toJson(),
    'frames': <String, Object?>{
      'painted': <String, Object?>{
        'a': _frames(summaryA)['painted'],
        'b': _frames(summaryB)['painted'],
      },
    },
    'rows': listed.map((_Row r) => r.toJson()).toList(),
    'unchanged': rows.length - listed.length,
    'timing': <String, Object?>{
      'gated': timed,
      if (!timed)
        'note': 'Milliseconds were not compared: only timing-mode medians '
            'are, and ${timingA == null ? 'A' : 'B'} has no timing pass. '
            'Rerun both with dusk:perf_run --timing.',
    },
  };
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

enum _Verdict { unchanged, improved, regressed }

/// One judged metric.
final class _Row {
  _Row({
    required this.metric,
    required this.a,
    required this.b,
    required this.deltaPct,
    required this.verdict,
    required this.severity,
    required this.info,
  });

  final String metric;

  /// A numeric measurement for a judged metric, or a `String` for a context
  /// row (a scenario or environment value that differs between the runs).
  final Object a;
  final Object b;

  /// Null when A never recorded the metric: there is nothing to divide by.
  final double? deltaPct;
  final _Verdict verdict;

  /// `error` / `warn` on a regression, `info` on an ungated row, else null.
  final String? severity;
  final bool info;

  int get _rank => switch ((info, verdict, severity)) {
        (false, _Verdict.regressed, 'error') => 0,
        (false, _Verdict.regressed, _) => 1,
        (false, _Verdict.improved, _) => 2,
        _ => 3,
      };

  static int byWeight(_Row x, _Row y) {
    final int byRank = x._rank.compareTo(y._rank);
    if (byRank != 0) return byRank;
    return (y.deltaPct?.abs() ?? double.infinity)
        .compareTo(x.deltaPct?.abs() ?? double.infinity);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'metric': metric,
        'a': a,
        'b': b,
        'deltaPct': deltaPct,
        'verdict': verdict.name,
        if (severity != null) 'severity': severity,
      };
}

/// Judges every metric in either map; a metric one side lacks is zero there.
List<_Row> _judge(
  Map<String, num> a,
  Map<String, num> b, {
  required Map<String, double> noiseA,
  required Map<String, double> noiseB,
  required PerfThresholds thresholds,
  String prefix = '',
  bool Function(String metric)? infoOnly,
  bool Function(String metric)? higherIsBetter,
}) {
  final List<String> metrics = <String>{...a.keys, ...b.keys}.toList()..sort();
  return <_Row>[
    for (final String metric in metrics)
      _judgeOne(
        metric: metric,
        name: '$prefix$metric',
        a: a[metric] ?? 0,
        b: b[metric] ?? 0,
        noise: _max(noiseA[metric] ?? 0, noiseB[metric] ?? 0),
        thresholds: thresholds,
        info: infoOnly?.call(metric) ?? false,
        higherIsBetter: higherIsBetter?.call(metric) ?? false,
      ),
  ];
}

_Row _judgeOne({
  required String metric,
  required String name,
  required num a,
  required num b,
  required double noise,
  required PerfThresholds thresholds,
  required bool info,
  required bool higherIsBetter,
}) {
  _Row row(_Verdict verdict, double? deltaPct, String? severity) => _Row(
        metric: name,
        a: a,
        b: b,
        deltaPct: deltaPct,
        verdict: verdict,
        severity: info ? 'info' : severity,
        info: info,
      );

  if (a == 0) {
    if (b == 0) return row(_Verdict.unchanged, 0, null);
    // A rise from zero is the good direction for a higher-is-better metric
    // (a cold cache that started hitting), never a regression.
    return higherIsBetter
        ? row(_Verdict.improved, null, null)
        : row(_Verdict.regressed, null, 'warn');
  }
  final double rawDeltaPct = _round1((b / a - 1) * 100);
  if ((b - a).abs() <= noise) {
    return row(_Verdict.unchanged, rawDeltaPct, null);
  }

  // A higher-is-better metric is judged against the same thresholds with the
  // sign flipped: a rise is the improvement, a fall is what regresses. The
  // percentage reported on the row ([rawDeltaPct]) always reads as "B versus
  // A", regardless of direction.
  final double deltaPct = higherIsBetter ? -rawDeltaPct : rawDeltaPct;
  if (deltaPct >= thresholds.errorPct) {
    return row(_Verdict.regressed, rawDeltaPct, 'error');
  }
  if (deltaPct >= thresholds.warnPct) {
    return row(_Verdict.regressed, rawDeltaPct, 'warn');
  }
  if (deltaPct <= -thresholds.warnPct) {
    return row(_Verdict.improved, rawDeltaPct, null);
  }
  return row(_Verdict.unchanged, rawDeltaPct, null);
}

/// An info row noting that context value [a] differs from [b] under
/// [metric] (a scenario name or an environment field), or null when they
/// agree, including when both are absent.
///
/// Never gated: a scenario or environment change explains why every other
/// row moved, it is not itself a regression or an improvement.
_Row? _contextRow(String metric, Object? a, Object? b) {
  if (a == b) return null;
  return _Row(
    metric: metric,
    a: a ?? 'absent',
    b: b ?? 'absent',
    deltaPct: null,
    verdict: _Verdict.unchanged,
    severity: 'info',
    info: true,
  );
}

Map<String, Object?> _env(Map<String, Object?> run) {
  final Object? env = run['env'];
  return env is Map<String, Object?> ? env : const <String, Object?>{};
}

Future<Map<String, Object?>> _read(String path) async {
  final String source = await File(path).readAsString();
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('$path is not a dusk:perf_run file.');
  }
  return decoded;
}

Map<String, Object?> _measuredSummary(Map<String, Object?> run, String side) {
  final Object? summary = run['summary'];
  if (summary is! Map<String, Object?>) {
    throw FormatException('Run $side has no summary; is it a dusk:perf_run '
        'file?');
  }
  if (summary['repeats'] is! int || (summary['repeats']! as int) == 0) {
    throw FormatException(
      'Run $side has no measured repeat: every one was refused '
      '(${summary['refused']}), so there is nothing to compare. Rerun it '
      'with the page in front.',
    );
  }
  return summary;
}

Map<String, Object?> _scenario(Map<String, Object?> run) {
  final Object? scenario = run['scenario'];
  return scenario is Map<String, Object?>
      ? scenario
      : const <String, Object?>{};
}

Map<String, Object?> _frames(Map<String, Object?> summary) {
  final Object? frames = summary['frames'];
  return frames is Map<String, Object?> ? frames : const <String, Object?>{};
}

Map<String, Object?>? _timing(Map<String, Object?> summary) {
  final Object? timing = summary['timing'];
  if (timing is! Map<String, Object?>) return null;
  final Object? repeats = timing['repeats'];
  return repeats is int && repeats > 0 ? timing : null;
}

bool _emulator(Map<String, Object?> run) {
  final Object? env = run['env'];
  return env is Map<String, Object?> && env['emulator'] == true;
}

Map<String, num> _numbers(Object? raw) => <String, num>{
      if (raw is Map<String, Object?>)
        for (final MapEntry<String, Object?> e in raw.entries)
          if (e.value is num) e.key: e.value! as num,
    };

/// The repeat-to-repeat range of each metric in [summary]'s [section].
Map<String, double> _noise(Map<String, Object?> summary, String section) {
  final Object? spread = summary['spread'];
  if (spread is! Map<String, Object?>) return const <String, double>{};
  final Object? entries = spread[section];
  if (entries is! Map<String, Object?>) return const <String, double>{};
  return <String, double>{
    for (final MapEntry<String, Object?> e in entries.entries)
      if (e.value case {'min': final num min, 'max': final num max})
        e.key: (max - min).toDouble(),
  };
}

bool _hasErrorRegression(Map<String, Object?> result) =>
    (result['rows']! as List<Object?>).cast<Map<String, Object?>>().any(
          (Map<String, Object?> r) =>
              r['verdict'] == 'regressed' && r['severity'] == 'error',
        );

void _printTable(ArtisanContext ctx, Map<String, Object?> result) {
  final Map<String, Object?> thresholds =
      result['thresholds']! as Map<String, Object?>;
  final Map<String, Object?> painted = (result['frames']!
      as Map<String, Object?>)['painted']! as Map<String, Object?>;
  final List<Map<String, Object?>> rows =
      (result['rows']! as List<Object?>).cast<Map<String, Object?>>();

  ctx.output.writeln(
    'perf_compare: ${result['verdict']} (per painted frame; warn '
    '+${thresholds['warn']}%, error +${thresholds['error']}%)',
  );
  ctx.output.writeln(
    'painted frames: ${painted['a']} -> ${painted['b']} (info, not gated)',
  );
  if (rows.isNotEmpty) {
    ctx.output.writeln(
      '${'metric'.padRight(44)}${'A'.padLeft(10)}${'B'.padLeft(10)}'
      '${'delta'.padLeft(9)}  verdict',
    );
  }
  for (final Map<String, Object?> row in rows.take(_kTableRowLimit)) {
    final Object? delta = row['deltaPct'];
    final String change = delta is num
        ? '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%'
        : 'new';
    final Object? severity = row['severity'];
    ctx.output.writeln(
      '${_fit('${row['metric']}', 44)}${_cell(row['a'])}${_cell(row['b'])}'
      '${change.padLeft(9)}  ${row['verdict']}'
      '${severity == null ? '' : ' ($severity)'}',
    );
  }
  if (rows.length > _kTableRowLimit) {
    ctx.output.writeln(
      '${rows.length - _kTableRowLimit} more rows; pass --json for all.',
    );
  }
  final Map<String, Object?> timing = result['timing']! as Map<String, Object?>;
  ctx.output.writeln(
    '${result['unchanged']} metrics unchanged.'
    '${timing['gated'] == true ? '' : ' ${timing['note']}'}',
  );
}

String _fit(String text, int width) => text.length < width
    ? text.padRight(width)
    : '${text.substring(0, width - 2)}~ ';

String _cell(Object? value) =>
    (value is num ? value.toStringAsFixed(2) : '-').padLeft(10);

double _max(double x, double y) => x > y ? x : y;

double _round1(double value) => (value * 10).roundToDouble() / 10;
