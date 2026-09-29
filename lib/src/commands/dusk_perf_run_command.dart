import 'dart:convert';
import 'dart:io';

// `hide Error`: the installer's `Error` result would shadow dart:core's.
import 'package:fluttersdk_artisan/artisan.dart' hide Error;
import 'package:meta/meta.dart';

import '../cdp/cdp_client.dart';
import '../perf/scenario.dart';
import 'json_output.dart';

/// Pause between the last step and `perf_end`. Flutter delivers FrameTiming
/// in batches about every 100 ms in debug and profile
/// (flutter/lib/src/scheduler/binding.dart:276-315), so a session closed on
/// the step's last frame reports a subset; three batches is enough margin.
const Duration _kSettleBeforeEnd = Duration(milliseconds: 300);

/// Insights the `--json` stdout carries, the bounded report's own limit; the
/// file keeps every one.
const int _kStdoutInsightLimit = 6;

/// How long a hot restart may take before ext.dusk.* answers again. Flutter
/// web recompiles on restart, which the harness measured at up to 16 s.
const Duration _kHotRestartTimeout = Duration(seconds: 90);

/// How long a relaunch may take: a profile build compiles from scratch.
const Duration _kRelaunchTimeout = Duration(seconds: 420);

/// How often the restart wait asks the app for its boot id.
const Duration _kBootPollInterval = Duration(milliseconds: 500);

/// How many candidates a role target asks `ext.dusk.observe` for: every
/// interactive node on a screen, so an index deep in a list still resolves.
const int _kObserveLimit = 5000;

/// The longest single in-app wait: well under the 10 s after which DWDS
/// abandons a service extension call on the web.
const int _kWaitSliceMs = 5000;

/// The gap between two ticks of one `wheel` step: one frame at 60 Hz.
const Duration _kWheelTickInterval = Duration(milliseconds: 16);

/// How long a target may take to show up before it "matched nothing": a
/// screen still settling after a navigate or a tap has not built it yet.
const Duration _kResolveBudget = Duration(seconds: 3);

/// The gap between two lookups of a target that has not shown up yet.
const Duration _kResolvePollInterval = Duration(milliseconds: 100);

/// The most lookups one target gets, so the budget holds on a driver whose
/// pause returns at once.
const int _kResolveMaxPolls = 30;

/// How long a setup navigate waits for the app to mount a Router. The boot
/// id answers from `main()`, which can still be awaiting its own boot or be
/// showing a loading screen before `runApp` builds the router.
const Duration _kRouterBudget = Duration(seconds: 10);

/// The most `ext.dusk.get_routes` reads that wait gets, so the budget holds
/// on a driver whose pause returns at once.
const int _kRouterMaxPolls = 100;

/// How many `ext.dusk.exceptions` entries a setup failure quotes.
const int _kDiagnosticExceptions = 3;

/// The longest exception message a setup failure quotes, in characters.
const int _kDiagnosticMessageChars = 200;

/// A run that cannot go on, with the sentence to print.
final class PerfRunException implements Exception {
  PerfRunException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything `dusk:perf_run` needs from outside the command: the app's
/// `ext.dusk.*` extensions, Chrome's DevTools, the runner's restart and the
/// clock. The production driver talks to artisan; a test drives a fake.
abstract interface class PerfRunDriver {
  /// Calls [method] on the running app. Throws on an extension error.
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params,
  ]);

  /// Sends one DevTools command to the page. Chrome only.
  Future<Map<String, dynamic>> cdp(
    String method, [
    Map<String, dynamic> params,
  ]);

  /// Restarts the app from scratch, a hot restart or a full relaunch as the
  /// build allows, and returns once `ext.dusk.*` answers again.
  Future<void> restart();

  Future<void> pause(Duration duration);

  /// Releases whatever the driver opened.
  Future<void> close();
}

/// What the run was measured on, beyond what the app reports about itself.
final class PerfRunEnvironment {
  const PerfRunEnvironment({
    required this.platform,
    this.device,
    this.emulator = false,
    this.restartMode = 'hot_restart',
    this.host = const <String, Object?>{},
    this.renderer = 'unknown',
  });

  final PerfPlatform platform;

  /// The runner's device id (`chrome`, `emulator-5554`, a simulator UDID).
  final String? device;

  /// An Android emulator or an iOS simulator, whose raster ms are not a
  /// device's.
  final bool emulator;

  /// `hot_restart` on a debug build, `relaunch` on one that cannot.
  final String restartMode;

  /// `uname`, CPU and core count of the machine that ran it.
  final Map<String, Object?> host;

  /// The rendering backend scraped from the run log, or `unknown`.
  final String renderer;
}

/// Opens the driver and describes the environment for one run.
typedef PerfRunConnector = Future<(PerfRunDriver, PerfRunEnvironment)> Function(
    ArtisanContext ctx, PerfPlatform? platform);

/// Runs a scenario's measured session several times and writes one file per
/// scenario, `<out>/<scenario>-<label>.json`:
///
/// ```text
/// artisan dusk:perf_run <scenario.yaml> [--label] [--out] [--repeat]
///   [--timing] [--against <baseline.yaml>] [--semantics-pass] [--json]
/// ```
///
/// Every repeat starts from the scenario's `setup` (so from its hot restart)
/// and is one attribution session: `perf_begin`, the steps, `perf_end` with
/// `full=true`. `--timing` interleaves timing-mode repeats, alternating the
/// order each round; `--against` runs a second scenario inside the same
/// rounds so both sides share the app's drift. `--semantics-pass` replays
/// the steps by coordinates with dusk's semantics handle released for the
/// timed window, reported as a separate `semanticsOff` series.
///
/// Exits 1 on a bad input, a step that cannot run, or when every attribution
/// repeat was refused; a refused repeat among measured ones is recorded and
/// left out of the medians.
class DuskPerfRunCommand extends ArtisanCommand {
  DuskPerfRunCommand({PerfRunConnector? connector})
      : _connector = connector ?? connectArtisanPerfRun;

  final PerfRunConnector _connector;

  @override
  String get name => 'dusk:perf_run';

  @override
  String get description =>
      'Run a perf scenario N times from a clean start and write medians, '
      'spread, insights and every repeat to <out>/<scenario>-<label>.json.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser
      ..addOption(
        'scenario',
        help: 'The scenario YAML (or the first argument).',
      )
      ..addOption(
        'label',
        help: 'Names this run in the file name; [a-z0-9_-] only.',
        defaultsTo: 'run',
      )
      ..addOption(
        'out',
        help: 'Directory the run files are written to.',
        defaultsTo: 'build/perf',
      )
      ..addOption(
        'repeat',
        help: 'Repeats per series; overrides the scenario\'s `repeat`.',
      )
      ..addOption(
        'platform',
        help: 'chrome, android or ios. Read from the running session when '
            'omitted.',
        allowed: PerfPlatform.values.map((PerfPlatform p) => p.name),
      )
      ..addOption(
        'against',
        help: 'A baseline scenario YAML run inside the same rounds, A and B '
            'alternating, and written to its own file.',
      )
      ..addFlag(
        'timing',
        help: 'Also run interleaved timing-mode repeats, the only '
            'milliseconds dusk:perf_compare gates on.',
        defaultsTo: false,
      )
      ..addFlag(
        'semantics-pass',
        help: 'Also replay the steps by coordinates with the semantics tree '
            'released for the timed window (the semanticsOff series).',
        defaultsTo: false,
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Every input is validated before the app is touched.
    final String? path =
        ctx.input.argument(0) ?? ctx.input.option('scenario') as String?;
    if (path == null || path.isEmpty) {
      ctx.output.error(
        'Usage: dusk:perf_run <scenario.yaml> [--label=<name>]: pass the '
        'scenario file.',
      );
      return 1;
    }
    final String label = (ctx.input.option('label') as String?) ?? 'run';
    if (!isSafePerfName(label)) {
      ctx.output.error(
        '--label "$label" must use [a-z0-9_-] only: it becomes part of the '
        'file name.',
      );
      return 1;
    }
    final String out = (ctx.input.option('out') as String?) ?? 'build/perf';
    final Object? rawRepeat = ctx.input.option('repeat');
    final int? repeat = _readInt(rawRepeat);
    if (rawRepeat != null && (repeat == null || repeat < 1)) {
      ctx.output.error('--repeat "$rawRepeat" must be a positive integer.');
      return 1;
    }
    final Object? platformName = ctx.input.option('platform');
    final PerfPlatform? platform = PerfPlatform.tryParse(platformName);
    if (platformName != null && platform == null) {
      ctx.output.error('--platform "$platformName" is not one of chrome, '
          'android, ios.');
      return 1;
    }
    final String? against = ctx.input.option('against') as String?;

    final List<PerfScenario> scenarios = <PerfScenario>[];
    for (final String file in <String>[path, if (against != null) against]) {
      final PerfScenario? scenario = await _load(ctx, file);
      if (scenario == null) return 1;
      scenarios.add(scenario);
    }
    if (scenarios.length == 2 && scenarios[0].name == scenarios[1].name) {
      ctx.output.error('--against names a scenario called '
          '"${scenarios[0].name}" too; the two run files would collide.');
      return 1;
    }

    // 2. Connect, then refuse a platform a scenario does not list.
    final PerfRunDriver driver;
    final PerfRunEnvironment env;
    try {
      (driver, env) = await _connector(ctx, platform);
    } on PerfRunException catch (e) {
      ctx.output.error(e.message);
      return 1;
    }

    try {
      for (final PerfScenario scenario in scenarios) {
        if (!scenario.platforms.contains(env.platform)) {
          ctx.output.error(
            'Scenario ${scenario.name} does not list ${env.platform.name}; '
            'it lists ${scenario.platforms.map((PerfPlatform p) => p.name).join(', ')}.',
          );
          return 1;
        }
      }

      // 3. Run every round.
      final _PerfRunner runner = _PerfRunner(
        driver,
        env,
        repeat: repeat ?? scenarios.first.repeat,
        timing: _readBool(ctx.input.option('timing')),
        semanticsPass: _readBool(ctx.input.option('semantics-pass')),
      );
      final List<_ScenarioRun> runs;
      try {
        runs = await runner.run(scenarios);
      } on PerfRunException catch (e) {
        ctx.output.error(e.message);
        return 1;
      }

      // 4. Write one file per scenario, then report the first.
      final List<(String, Map<String, Object?>)> written =
          <(String, Map<String, Object?>)>[];
      for (final _ScenarioRun run in runs) {
        final Map<String, Object?> file = runner.fileFor(
          run,
          label,
          interleavedWith: runs.length == 2
              ? runs.firstWhere((_ScenarioRun r) => r != run).scenario.name
              : null,
        );
        written.add((await _write(out, run.scenario.name, label, file), file));
      }
      return _report(ctx, written);
    } finally {
      await driver.close();
    }
  }

  Future<PerfScenario?> _load(ArtisanContext ctx, String path) async {
    try {
      return PerfScenario.parse(await File(path).readAsString());
    } on PerfScenarioException catch (e) {
      ctx.output.error('$path: $e');
    } on FileSystemException catch (e) {
      ctx.output.error('Cannot read scenario $path: ${e.message}');
    }
    return null;
  }

  Future<String> _write(
    String out,
    String name,
    String label,
    Map<String, Object?> file,
  ) async {
    final File target = File('$out/$name-$label.json').absolute;
    await target.parent.create(recursive: true);
    await target.writeAsString(
      const JsonEncoder.withIndent('  ').convert(file),
    );
    return target.path;
  }

  int _report(
    ArtisanContext ctx,
    List<(String, Map<String, Object?>)> written,
  ) {
    final (String path, Map<String, Object?> file) = written.first;
    final Map<String, Object?> summary =
        file['summary']! as Map<String, Object?>;
    final int measured = summary['repeats']! as int;
    final int refused = summary['refused']! as int;
    final String name =
        (file['scenario']! as Map<String, Object?>)['name']! as String;

    // Every repeat refused is a run with no measurement in it: a file of
    // refusals written with exit 0 would be chained on as if it were one.
    final bool empty = written.any(
      ((String, Map<String, Object?>) w) =>
          (w.$2['summary']! as Map<String, Object?>)['repeats'] == 0,
    );

    emitEnvelope(ctx, _stdoutShape(file, path), () {
      if (empty) return;
      final Map<String, Object?> frames =
          summary['frames']! as Map<String, Object?>;
      ctx.output.success(
        'perf_run $name: $measured of ${measured + refused} attribution '
        'repeats measured ($refused refused), median ${frames['painted']} '
        'painted frames. Wrote $path.',
      );
      final List<Object?> insights = file['insights']! as List<Object?>;
      if (insights.isNotEmpty) {
        final Map<String, Object?> top =
            insights.first! as Map<String, Object?>;
        ctx.output.writeln(
          'Top insight of the median repeat: [${top['severity']}] '
          '${top['id']}: ${top['title']}.',
        );
      }
      if (file['semanticsPass'] != null) {
        ctx.output.writeln(
          'Semantics pass: ${file['semanticsPass']}'
          '${file['semanticsPassReason'] == null ? '' : ', ${file['semanticsPassReason']}'}.',
        );
      }
      for (final (String other, _) in written.skip(1)) {
        ctx.output.writeln('Also wrote $other.');
      }
    });

    if (!empty) return 0;
    ctx.output.error(
      'Every attribution repeat of a scenario was refused, so there is no '
      'measurement: the engine drew too few frames. Bring the page to '
      'front, check the steps drive something that renders, and rerun. The '
      'refusals are in $path.',
    );
    return 1;
  }
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

/// The middle of [values], or the mean of the two middle ones.
///
/// Throws [ArgumentError] on an empty list: a median of nothing is not zero.
double perfMedian(List<num> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'must not be empty');
  }
  final List<double> sorted = values.map((num v) => v.toDouble()).toList()
    ..sort();
  final int mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// `{min, max, rangePct}` of [values]: the range as a percentage of the
/// median, null when the median is zero.
Map<String, Object?> perfSpread(List<num> values) {
  final double min = values.map((num v) => v.toDouble()).reduce(_min);
  final double max = values.map((num v) => v.toDouble()).reduce(_max);
  final double median = perfMedian(values);
  return <String, Object?>{
    'min': min,
    'max': max,
    'rangePct': median == 0 ? null : _round(((max - min) / median) * 100, 1),
  };
}

/// Every count in a `perf_end` report, per painted frame, by a flat name.
///
/// - `blocks.<name>` from `summary.blocksByCount`;
/// - `<section>.<key>` for a counter `{count, perFrame}`;
/// - `<section>.<key>.<name>` for a ranked counter row
///   `[name, count, perFrame]`.
///
/// Gauges (a bare number, such as wind's `cacheSize`) are not counts and are
/// left out. A missing `perFrame` is computed from the count and the painted
/// frames, so nothing is ever compared raw.
Map<String, double> perfPerFrameMetrics(Map<String, dynamic> report) {
  final Map<String, dynamic> summary = _map(report['summary']);
  final num painted = _num(_map(summary['frames'])['painted']);
  double perFrame(Object? given, Object? count) => given is num
      ? given.toDouble()
      : painted == 0
          ? 0
          : _num(count) / painted;

  final Map<String, double> metrics = <String, double>{};
  for (final Object? block in _list(summary['blocksByCount'])) {
    final Map<String, dynamic> row = _map(block);
    metrics['blocks.${row['name']}'] = perFrame(row['perFrame'], row['count']);
  }
  final Map<String, dynamic> counters = _map(report['counters']);
  for (final String section in const <String>['wind', 'magic']) {
    for (final MapEntry<String, dynamic> entry
        in _map(counters[section]).entries) {
      final Object? value = entry.value;
      if (value is Map<String, dynamic>) {
        metrics['$section.${entry.key}'] =
            perFrame(value['perFrame'], value['count']);
      } else if (value is List<dynamic>) {
        for (final Object? row in value) {
          if (row is List<dynamic> && row.length >= 2) {
            metrics['$section.${entry.key}.${row[0]}'] =
                perFrame(row.length > 2 ? row[2] : null, row[1]);
          }
        }
      }
    }
  }
  return metrics;
}

/// The frame durations of a report, in ms: build and raster p50 and p90.
Map<String, double> perfMsMetrics(Map<String, dynamic> report) {
  final Map<String, dynamic> frames = _map(_map(report['summary'])['frames']);
  return <String, double>{
    for (final String thread in const <String>['buildMs', 'rasterMs'])
      for (final String pct in const <String>['p50', 'p90'])
        if (_map(frames[thread])[pct] is num)
          '$thread.$pct': _num(_map(frames[thread])[pct]).toDouble(),
  };
}

/// One series of `perf_end` reports reduced to medians and spread.
///
/// Refused reports are counted and left out; a series with none measured
/// carries only `{repeats: 0, refused: n}`. A report whose frames could not
/// be placed in its session window (`coverage.sessionClockMismatch`) is left
/// out the same way and counted as `unplaced`, present only when non-zero: it
/// kept frames from outside its session. A metric one report lacks counts
/// as zero there, because a block that did not build was built zero times.
Map<String, Object?> summarizePerfSeries(List<Map<String, dynamic>> reports) {
  final List<Map<String, dynamic>> answered =
      reports.where((Map<String, dynamic> r) => r['refused'] != true).toList();
  final List<Map<String, dynamic>> measured = answered
      .where(
        (Map<String, dynamic> r) =>
            _map(r['coverage'])['sessionClockMismatch'] != true,
      )
      .toList();
  final Map<String, Object?> summary = <String, Object?>{
    'repeats': measured.length,
    'refused': reports.length - answered.length,
    if (answered.length > measured.length)
      'unplaced': answered.length - measured.length,
  };
  if (measured.isEmpty) return summary;

  // 1. Frame counts, informational: the gate never reads them raw.
  summary['frames'] = <String, Object?>{
    for (final String key in const <String>[
      'count',
      'painted',
      'dropped',
      'overBudget',
    ])
      key: _plain(
        perfMedian(<num>[
          for (final Map<String, dynamic> r in measured)
            _num(_map(_map(r['summary'])['frames'])[key]),
        ]),
      ),
  };

  // 2. Per-frame counts and durations, each with its spread.
  final Map<String, Object?> spread = <String, Object?>{};
  for (final (
        String section,
        Map<String, double> Function(Map<String, dynamic>) read
      ) in <(String, Map<String, double> Function(Map<String, dynamic>))>[
    ('perFrame', perfPerFrameMetrics),
    ('ms', perfMsMetrics),
  ]) {
    final List<Map<String, double>> rows = measured.map(read).toList();
    final List<String> names = <String>{
      for (final Map<String, double> row in rows) ...row.keys,
    }.toList()
      ..sort();
    if (names.isEmpty) continue;
    final Map<String, Object?> medians = <String, Object?>{};
    final Map<String, Object?> ranges = <String, Object?>{};
    for (final String name in names) {
      final List<double> values = <double>[
        for (final Map<String, double> row in rows) row[name] ?? 0,
      ];
      medians[name] = _round(perfMedian(values), 4);
      ranges[name] = perfSpread(values);
    }
    summary[section] = medians;
    spread[section] = ranges;
  }
  summary['spread'] = spread;
  return summary;
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

/// The platform named by [requested], or read from the session's [state].
///
/// Throws [PerfRunException] when neither settles it.
PerfPlatform resolvePerfPlatform(
  Map<String, dynamic>? state,
  String? requested,
) {
  if (requested != null) {
    final PerfPlatform? platform = PerfPlatform.tryParse(requested);
    if (platform != null) return platform;
    throw PerfRunException(
      '--platform "$requested" is not one of chrome, android, ios.',
    );
  }
  final String device = '${state?['device'] ?? ''}';
  final String lower = device.toLowerCase();
  if (state?['cdpPort'] != null ||
      lower == 'chrome' ||
      lower == 'web-server' ||
      lower == 'edge') {
    return PerfPlatform.chrome;
  }
  if (lower.startsWith('emulator-') || lower.contains('android')) {
    return PerfPlatform.android;
  }
  if (_kSimulatorUdid.hasMatch(device) ||
      lower.contains('ios') ||
      lower.contains('iphone')) {
    return PerfPlatform.ios;
  }
  throw PerfRunException(
    'Cannot tell which platform device "$device" is; pass '
    '--platform=chrome|android|ios.',
  );
}

/// `relaunch` when the session's build cannot hot restart (a profile or
/// release build), else `hot_restart`.
String perfRestartMode(Map<String, dynamic>? state) {
  final Object? args = state?['flutterArgs'];
  final bool compiled = state?['profile'] == 'static' ||
      (args is List<dynamic> &&
          (args.contains('--profile') || args.contains('--release')));
  return compiled ? 'relaunch' : 'hot_restart';
}

/// The rendering backend the engine logged, as `impeller-<backend>`, or
/// `unknown` when the run log says nothing about it.
String scrapePerfRenderer(String? log) {
  if (log == null) return 'unknown';
  final Iterable<RegExpMatch> matches =
      RegExp(r'Using the Impeller rendering backend(?: \(([^)]+)\))?')
          .allMatches(log);
  if (matches.isEmpty) return 'unknown';
  final String? backend = matches.last.group(1);
  return backend == null ? 'impeller' : 'impeller-${backend.toLowerCase()}';
}

/// The production connector: artisan's VM Service client, the session's
/// state file and CDP port, and the host's own description.
Future<(PerfRunDriver, PerfRunEnvironment)> connectArtisanPerfRun(
  ArtisanContext ctx,
  PerfPlatform? platform,
) async {
  final VmServiceClient? client = ctx.vmClient;
  if (client == null) {
    throw PerfRunException(
      'dusk:perf_run needs a running app. Run `artisan start` first.',
    );
  }
  final Map<String, dynamic>? state = await StateFile.read();
  final PerfPlatform resolved = platform ?? resolvePerfPlatform(state, null);
  final int? cdpPort = state?['cdpPort'] as int?;
  if (resolved == PerfPlatform.chrome && cdpPort == null) {
    throw PerfRunException(
      'CDP not enabled, and Chrome needs it: every session is brought to '
      'front first, since a background tab draws no frames. Run `artisan '
      'start --cdp-port=9222` first.',
    );
  }
  final String device = '${state?['device'] ?? ''}';
  final String restartMode = perfRestartMode(state);
  return (
    _ArtisanPerfRunDriver(
      client,
      cdpPort: cdpPort,
      relaunch: restartMode == 'relaunch',
      profileStatic: state?['profile'] == 'static',
    ),
    PerfRunEnvironment(
      platform: resolved,
      device: device.isEmpty ? null : device,
      emulator:
          device.startsWith('emulator-') || _kSimulatorUdid.hasMatch(device),
      restartMode: restartMode,
      host: await _hostInfo(),
      renderer: scrapePerfRenderer(await _runLog()),
    ),
  );
}

// ---------------------------------------------------------------------------
// The runner
// ---------------------------------------------------------------------------

/// The three series a scenario can produce.
enum _Series { attribution, timing, semanticsOff }

/// One scenario's reports and what its semantics pass needs.
final class _ScenarioRun {
  _ScenarioRun(this.scenario);

  final PerfScenario scenario;
  final Map<_Series, List<Map<String, dynamic>>> reports =
      <_Series, List<Map<String, dynamic>>>{
    for (final _Series series in _Series.values)
      series: <Map<String, dynamic>>[],
  };

  /// Per report in [reports], where and how long each step's target took to
  /// resolve: `{step, verb, phase: beforeBegin|inWindow, resolveMs}`. An
  /// `inWindow` resolve is cost the session measured.
  final Map<_Series, List<List<Map<String, Object?>>>> resolves =
      <_Series, List<List<Map<String, Object?>>>>{
    for (final _Series series in _Series.values)
      series: <List<Map<String, Object?>>>[],
  };

  /// The dispatch points recorded with the tree on, by step index: `point`
  /// for a tap or a wheel, `from` and `to` for a drag.
  final Map<int, Map<String, dynamic>> points = <int, Map<String, dynamic>>{};

  /// Why the semantics pass cannot drive this scenario, or null.
  String? unsupported;
}

/// Drives the rounds and assembles the run files.
final class _PerfRunner {
  _PerfRunner(
    this.driver,
    this.env, {
    required this.repeat,
    required this.timing,
    required this.semanticsPass,
  });

  final PerfRunDriver driver;
  final PerfRunEnvironment env;
  final int repeat;
  final bool timing;
  final bool semanticsPass;

  /// The payload of the current setup's last honored navigate, for
  /// [_diagnose]; null before the first.
  Map<String, dynamic>? _lastNavigate;

  bool get _chrome => env.platform == PerfPlatform.chrome;

  Future<List<_ScenarioRun>> run(List<PerfScenario> scenarios) async {
    final List<_ScenarioRun> runs =
        scenarios.map((PerfScenario s) => _ScenarioRun(s)).toList();
    if (semanticsPass) {
      for (final _ScenarioRun run in runs) {
        run.unsupported = _unsupportedReason(run.scenario);
      }
    }

    // 1. Rounds. Each round runs every unit once and the next reverses the
    //    order, so drift in the app (a warming cache, a growing heap) lands
    //    on both modes and both scenarios alike.
    final List<(_ScenarioRun, _Series)> units = <(_ScenarioRun, _Series)>[
      for (final _ScenarioRun run in runs) ...<(_ScenarioRun, _Series)>[
        (run, _Series.attribution),
        if (timing) (run, _Series.timing),
      ],
    ];
    for (int i = 0; i < repeat; i++) {
      for (final (_ScenarioRun run, _Series series)
          in i.isEven ? units : units.reversed) {
        await _unit(
          run,
          series,
          record: semanticsPass && i == 0 && series == _Series.attribution,
        );
      }
    }

    // 2. The semantics pass, after the recording round. A step it cannot
    //    replay marks the scenario unsupported rather than failing the run.
    if (!semanticsPass) return runs;
    for (int i = 0; i < repeat; i++) {
      for (final _ScenarioRun run in runs) {
        if (run.unsupported != null) continue;
        try {
          await _unit(run, _Series.semanticsOff, record: false);
        } on PerfRunException catch (e) {
          run.unsupported = e.message;
          run.reports[_Series.semanticsOff]!.clear();
          run.resolves[_Series.semanticsOff]!.clear();
        }
      }
    }
    return runs;
  }

  /// One session: setup, begin, the steps, end.
  Future<void> _unit(
    _ScenarioRun run,
    _Series series, {
    required bool record,
  }) async {
    final PerfScenario scenario = run.scenario;

    // 1. The same starting state for every repeat.
    await _prepare(scenario);
    if (_chrome) await driver.cdp('Page.bringToFront');

    // 2. A target no earlier step can move resolves now, outside the window;
    //    the rest resolve inside it, right before their step, and say so in
    //    `resolves`. The pass replays by coordinates and resolves nothing.
    final List<Map<String, Object?>> resolves = <Map<String, Object?>>[];
    final Map<int, _Resolved> resolved = series == _Series.semanticsOff
        ? const <int, _Resolved>{}
        : await _preResolve(scenario, resolves);

    // 3. The timed window. A failing step is held rather than thrown so the
    //    session still closes: perf_end restores the profiling flags, and a
    //    released semantics handle must never outlive the window. A release
    //    that left the tree on ends the window at once: what would follow is
    //    the attribution series again, reported as semantics off.
    await _call(
      'ext.dusk.perf_begin',
      <String, String>{
        'mode': series == _Series.timing ? 'timing' : 'attribution',
      },
      scenario.name,
    );
    bool released = false;
    Object? failure;
    StackTrace? trace;
    try {
      if (series == _Series.semanticsOff) {
        // Marked before the call: a release that landed but whose answer was
        // lost still needs its acquire.
        released = true;
        final Map<String, dynamic> answer = await _call(
          'ext.dusk.semantics_hold',
          <String, String>{'action': 'release'},
          scenario.name,
        );
        if (answer['semanticsEnabled'] != false) {
          throw PerfRunException(_semanticsHeldReason(answer));
        }
      }
      for (int i = 0; i < scenario.steps.length; i++) {
        final PerfStep step = scenario.steps[i];
        if (!step.runsOn(env.platform)) continue;
        await _step(
          run,
          i,
          step,
          series: series,
          record: record,
          resolved: resolved[i],
          resolves: resolves,
        );
      }
      await driver.pause(_kSettleBeforeEnd);
    } catch (e, st) {
      failure = e;
      trace = st;
    }

    // 4. Close it whatever happened, then re-acquire. perf_end goes first: the
    //    acquire's frame rebuilds the whole tree, which is not the app's cost,
    //    and perf_end reads `env.semanticsEnabled` for the window it closes.
    //    A failed perf_end is held like a failed step so the acquire still
    //    runs; the first failure is the one rethrown.
    Map<String, dynamic>? report;
    try {
      report = await _call(
        'ext.dusk.perf_end',
        <String, String>{'full': 'true'},
        scenario.name,
      );
    } catch (e, st) {
      failure ??= e;
      trace ??= st;
    }
    if (released) {
      try {
        await _call(
          'ext.dusk.semantics_hold',
          <String, String>{'action': 'acquire'},
          scenario.name,
        );
      } on PerfRunException catch (e, st) {
        failure ??= e;
        trace ??= st;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    run.reports[series]!.add(report!);
    run.resolves[series]!.add(resolves);
  }

  /// Runs the scenario's setup. Every failure but a restart's carries
  /// [_diagnose]: the route the app is on, the last navigate's payload and
  /// the newest exceptions, since "did not appear" alone does not say which
  /// screen it did not appear on.
  Future<void> _prepare(PerfScenario scenario) async {
    _lastNavigate = null;
    await _viewport(scenario);
    for (final (int i, PerfSetupStep step) in scenario.setup.indexed) {
      // 1. A restart names the app's last answer itself, and an app that is
      //    not back has nothing to diagnose with.
      if (step.verb == PerfSetupVerb.hotRestart) {
        await driver.restart();
        await _viewport(scenario);
        continue;
      }
      final PerfStep? gesture = step.gesture;
      if (gesture != null && !gesture.runsOn(env.platform)) continue;

      // 2. Everything else says where the app was when it failed.
      final String where = '${scenario.name} setup[$i] '
          '(${gesture?.verb.wire ?? step.verb.wire})';
      try {
        await _setupStep(step, where);
      } on Exception catch (e) {
        throw PerfRunException(
          '${e is PerfRunException ? e.message : '$where: $e'}\n'
          '${await _diagnose()}',
        );
      }
    }
  }

  /// One setup entry other than `hot_restart`, which [_prepare] runs itself.
  /// Throws [PerfRunException] prefixed with [where].
  Future<void> _setupStep(PerfSetupStep step, String where) async {
    switch (step.verb) {
      case PerfSetupVerb.hotRestart:
        throw StateError('_prepare runs hot_restart itself.');
      case PerfSetupVerb.gesture:
        try {
          await _drive(step.gesture!, record: false);
        } on Exception catch (e) {
          throw PerfRunException(
            '$where: ${e is PerfRunException ? e.message : e}',
          );
        }
      case PerfSetupVerb.navigate:
        await _setupNavigate(step.argument!, where);
      case PerfSetupVerb.waitForText:
        // In slices: DWDS cuts any service extension call at 10 s and
        // answers -32603, so one in-app wait of the whole budget died on
        // every slow web restart. Each slice is a full in-app wait; the
        // budget is spent slice by slice rather than by the host clock.
        bool matched = false;
        final int budget = step.timeoutMs ?? kPerfWaitForTextTimeoutMs;
        for (int left = budget; left > 0 && !matched;) {
          final int slice = left < _kWaitSliceMs ? left : _kWaitSliceMs;
          final Map<String, dynamic> result = await _call(
            'ext.dusk.wait_for',
            <String, String>{
              'text': step.argument!,
              'timeoutMs': '$slice',
            },
            where,
          );
          matched = result['matched'] == true;
          left -= slice;
        }
        if (!matched) {
          throw PerfRunException(
            '$where: "${step.argument}" did not appear within '
            '$budget ms.',
          );
        }
      case PerfSetupVerb.waitForNetworkIdle:
        await _call(
          'ext.dusk.wait_for_network_idle',
          const <String, String>{},
          where,
        );
    }
  }

  /// Navigates to [route] and holds the app to it.
  ///
  /// The app has to be routable first ([_awaitRouter]). A `navigated: false`
  /// then fails with the payload unless the route lands within
  /// [_kResolveBudget] ([_awaitLanding]): a dropped route never lands and a
  /// redirected one lands elsewhere, and every later step would run on the
  /// wrong screen. The router's URI read right after is read again once the
  /// network is idle, since a first fetch that answers 401 redirects away
  /// afterwards.
  Future<void> _setupNavigate(String route, String where) async {
    // 1. A navigate is verified against the mounted Router, so one sent
    //    before the Router exists answers false even when it lands later.
    await _awaitRouter(where);

    // 2. The router has to honor the route, if not within the navigate's
    //    own two-frame read then shortly after it.
    Map<String, dynamic> payload = await _call(
      'ext.dusk.navigate',
      <String, String>{
        'route': route,
        'includeSnapshot': 'false',
      },
      where,
    );
    if (payload['navigated'] != true) {
      if (!await _awaitLanding(route, where)) {
        throw PerfRunException(
          '$where: the router did not honor "$route"; ext.dusk.navigate '
          'answered ${jsonEncode(payload)}.',
        );
      }
      payload = <String, dynamic>{...payload, 'landedLate': true};
    }
    _lastNavigate = payload;

    // 3. And the app has to stay there once its first fetches are done.
    final Object? landed = (await _call(
      'ext.dusk.get_routes',
      const <String, String>{},
      where,
    ))['uri'];
    await _call(
      'ext.dusk.wait_for_network_idle',
      const <String, String>{},
      where,
    );
    final Object? settled = (await _call(
      'ext.dusk.get_routes',
      const <String, String>{},
      where,
    ))['uri'];
    if (settled != landed) {
      throw PerfRunException(
        '$where: navigating to "$route" landed on "$landed", and once the '
        'network was idle the app had moved to "$settled".',
      );
    }
  }

  /// Whether the Router's `uri` reaches [route] (the same path or one under
  /// it, the match `ext.dusk.navigate` makes) within [_kResolveBudget], read
  /// every [_kResolvePollInterval] and at most [_kResolveMaxPolls] times.
  ///
  /// `ext.dusk.navigate` reads the Router two frames after dispatching. A
  /// Router that mounted a moment earlier is still applying its first
  /// location then and reports a transient one, so the navigate answers
  /// false for a route that lands right after: measured on a web hot
  /// restart, false as the Router mounted and true 300 ms later. Only reads:
  /// a second dispatch would stack a pushed route twice.
  Future<bool> _awaitLanding(String route, String where) async {
    final String wanted = _routePath(route);
    final Stopwatch clock = Stopwatch()..start();
    for (int poll = 1;; poll++) {
      final Object? uri = (await _call(
        'ext.dusk.get_routes',
        const <String, String>{},
        where,
      ))['uri'];
      if (uri is String) {
        final String path = _routePath(uri);
        if (path == wanted || path.startsWith('$wanted/')) return true;
      }
      if (poll >= _kResolveMaxPolls || clock.elapsed >= _kResolveBudget) {
        return false;
      }
      await driver.pause(_kResolvePollInterval);
    }
  }

  /// Waits until `ext.dusk.get_routes` reports a mounted Router's `uri`,
  /// read every [_kResolvePollInterval] for up to [_kRouterBudget] (and at
  /// most [_kRouterMaxPolls] reads).
  ///
  /// `ext.dusk.boot_id` answers once `DuskPlugin.install()` has run, and a
  /// host that installs dusk before its own boot (magic_devtools' documented
  /// order) or shows a loading screen first has no Router yet. Waiting here
  /// rather than in the restart keeps a scenario that never navigates, or an
  /// app with no Router at all, free of it.
  ///
  /// Throws [PerfRunException] prefixed with [where] when the budget runs out,
  /// or at once when the answer has no `uri` key: the app runs a dusk older
  /// than this CLI.
  Future<void> _awaitRouter(String where) async {
    final Stopwatch clock = Stopwatch()..start();
    for (int poll = 1;; poll++) {
      final Map<String, dynamic> routes = await _call(
        'ext.dusk.get_routes',
        const <String, String>{},
        where,
      );
      if (!routes.containsKey('uri')) {
        throw PerfRunException(
          '$where: ext.dusk.get_routes answered no "uri", so the app runs a '
          'dusk older than this CLI. Relaunch the app so it runs the dusk '
          'this CLI ships with.',
        );
      }
      if (routes['uri'] is String) return;
      if (poll >= _kRouterMaxPolls || clock.elapsed >= _kRouterBudget) {
        throw PerfRunException(
          '$where: no Router was mounted within ${_kRouterBudget.inSeconds} s '
          '($poll reads of ext.dusk.get_routes), and a navigate is verified '
          'against the Router\'s location.',
        );
      }
      await driver.pause(_kResolvePollInterval);
    }
  }

  /// One line on where the app is: its route, the last setup navigate's
  /// payload and its newest exceptions. A diagnostic call that fails is named
  /// in place of its answer: the failure it explains stands either way.
  Future<String> _diagnose() async {
    final String route = await _describe(
      'ext.dusk.get_routes',
      const <String, String>{},
      (Map<String, dynamic> r) {
        final Object? uri = r['uri'];
        final Object? page = r['location'];
        final Object? title = r['title'];
        return 'route ${uri is String ? '"$uri"' : 'none (no Router mounted)'}'
            '${page is String && page.isNotEmpty ? ' (page "$page")' : ''}'
            '${title is String && title.isNotEmpty ? ' (title "$title")' : ''}';
      },
    );
    final Map<String, dynamic>? payload = _lastNavigate;
    final String navigate = payload == null
        ? 'no setup navigate ran'
        : 'last setup navigate answered ${jsonEncode(payload)}';
    final String exceptions = await _describe(
      'ext.dusk.exceptions',
      const <String, String>{'limit': '$_kDiagnosticExceptions'},
      (Map<String, dynamic> r) {
        final List<dynamic> entries = _list(r['exceptions']);
        if (entries.isEmpty) return 'last exceptions: none';
        return 'last exceptions: ${entries.map(_exceptionLine).join(' | ')}';
      },
    );
    return 'Diagnostics: $route; $navigate; $exceptions.';
  }

  Future<String> _describe(
    String method,
    Map<String, String> params,
    String Function(Map<String, dynamic> result) render,
  ) async {
    try {
      return render(await driver.call(method, params));
    } on Exception catch (e) {
      return '$method failed ($e)';
    }
  }

  Future<void> _viewport(PerfScenario scenario) async {
    final ({int width, int height})? viewport = scenario.viewport;
    if (!_chrome || viewport == null) return;
    await _resize(viewport.width, viewport.height);
  }

  Future<void> _resize(int width, int height) => driver.cdp(
        'Emulation.setDeviceMetricsOverride',
        <String, dynamic>{
          'width': width,
          'height': height,
          // 0 keeps the browser's own device pixel ratio.
          'deviceScaleFactor': 0,
          'mobile': false,
        },
      );

  /// Runs step [index]: driving it through the live tree, with the target
  /// [resolved] before `perf_begin` when there is one, or replaying its
  /// recorded points with the tree released.
  Future<void> _step(
    _ScenarioRun run,
    int index,
    PerfStep step, {
    required _Series series,
    required bool record,
    required _Resolved? resolved,
    required List<Map<String, Object?>> resolves,
  }) async {
    final String where =
        '${run.scenario.name} steps[$index] (${step.verb.wire})';
    try {
      if (series == _Series.semanticsOff) {
        await _replay(run, index, step);
      } else {
        final Map<String, dynamic>? points = await _drive(
          step,
          record: record,
          resolved: resolved,
          onResolved: (Stopwatch clock) => resolves.add(
            _resolveEntry(index, step, 'inWindow', clock),
          ),
        );
        if (points != null) run.points[index] = points;
      }
    } on Exception catch (e) {
      throw PerfRunException(
          '$where: ${e is PerfRunException ? e.message : e}');
    }
  }

  /// Resolves, before `perf_begin`, the target of each step no earlier step
  /// can move ([PerfStepVerb.movesTargets]), and a wheel's hover point with
  /// it; stops after the first step that can move what follows. Each resolve
  /// is added to [resolves] as `beforeBegin`.
  ///
  /// Throws [PerfRunException] with [_diagnose] when a target does not show
  /// up: no session is open yet, so there is nothing to close.
  Future<Map<int, _Resolved>> _preResolve(
    PerfScenario scenario,
    List<Map<String, Object?>> resolves,
  ) async {
    final Map<int, _Resolved> resolved = <int, _Resolved>{};
    for (int i = 0; i < scenario.steps.length; i++) {
      final PerfStep step = scenario.steps[i];
      if (!step.runsOn(env.platform)) continue;
      if (step.verb.takesTarget) {
        final Stopwatch clock = Stopwatch()..start();
        try {
          final String ref = await _resolve(step.target!);
          resolved[i] = (
            ref: ref,
            point: step.verb == PerfStepVerb.wheel ? await _hover(ref) : null,
          );
        } on Exception catch (e) {
          throw PerfRunException(
            '${scenario.name} steps[$i] (${step.verb.wire}), resolved before '
            'perf_begin: ${e is PerfRunException ? e.message : e}\n'
            '${await _diagnose()}',
          );
        }
        resolves.add(_resolveEntry(i, step, 'beforeBegin', clock));
      }
      if (step.verb.movesTargets) break;
    }
    return resolved;
  }

  Map<String, Object?> _resolveEntry(
    int index,
    PerfStep step,
    String phase,
    Stopwatch clock,
  ) =>
      <String, Object?>{
        'step': index,
        'verb': step.verb.wire,
        'phase': phase,
        'resolveMs': _round(clock.elapsedMicroseconds / 1000, 1),
      };

  /// Hovers [ref] and answers the point it hovered: what a mouse does before
  /// it wheels, and where the wheel then goes.
  Future<Map<String, dynamic>> _hover(String ref) async => _map(
        (await driver.call(
          'ext.dusk.hover',
          <String, String>{
            'ref': ref,
            'reportPoint': 'true',
            'includeSnapshot': 'false',
          },
        ))['point'],
      );

  /// Drives [step] through the live tree. Returns the dispatch points when
  /// [record] asks for them and the verb has any, for the semantics pass to
  /// replay; null otherwise.
  ///
  /// The target is [resolved] when [_preResolve] got it, else resolved here,
  /// and [onResolved] is handed the clock of that resolve.
  Future<Map<String, dynamic>?> _drive(
    PerfStep step, {
    required bool record,
    _Resolved? resolved,
    void Function(Stopwatch clock)? onResolved,
  }) async {
    const Map<String, String> quiet = <String, String>{
      'includeSnapshot': 'false',
    };
    final Map<String, String> report = <String, String>{
      if (record) 'reportPoint': 'true',
    };
    Future<String> target() async {
      final _Resolved? early = resolved;
      if (early != null) return early.ref;
      final Stopwatch clock = Stopwatch()..start();
      final String ref = await _resolve(step.target!);
      onResolved?.call(clock);
      return ref;
    }

    switch (step.verb) {
      case PerfStepVerb.tap:
        final Map<String, dynamic> result = await driver.call(
          'ext.dusk.tap',
          <String, String>{
            'ref': await target(),
            ...quiet,
            ...report,
          },
        );
        return record ? <String, dynamic>{'point': result['point']} : null;
      case PerfStepVerb.wheel:
        final Map<String, dynamic> point =
            resolved?.point ?? await _hover(await target());
        await _wheel(point, step);
        return record ? <String, dynamic>{'point': point} : null;
      case PerfStepVerb.drag:
        final Map<String, dynamic> result = await driver.call(
          'ext.dusk.drag',
          <String, String>{
            'startRef': await target(),
            'dx': '${step.dx}',
            'dy': '${step.dy}',
            ...quiet,
            ...report,
          },
        );
        return record
            ? <String, dynamic>{'from': result['from'], 'to': result['to']}
            : null;
      case PerfStepVerb.fill:
      case PerfStepVerb.type:
        await driver.call(
          'ext.dusk.${step.verb.wire}',
          <String, String>{
            'ref': await target(),
            'text': step.text!,
            ...quiet,
          },
        );
      case PerfStepVerb.scroll:
        await driver.call(
          'ext.dusk.scroll',
          <String, String>{
            'ref': await target(),
            'dx': '${step.dx}',
            'dy': '${step.dy}',
            ...quiet,
          },
        );
      case PerfStepVerb.pressKey:
      case PerfStepVerb.navigate:
      case PerfStepVerb.resize:
      case PerfStepVerb.wait:
        await _untargeted(step);
    }
    return null;
  }

  /// Replays a step by the points [_drive] recorded. Nothing here resolves a
  /// target: with the handle released there is no tree to resolve through.
  Future<void> _replay(_ScenarioRun run, int index, PerfStep step) async {
    final Map<String, dynamic>? recorded = run.points[index];
    switch (step.verb) {
      case PerfStepVerb.tap:
        final Map<String, dynamic> point = _recorded(recorded, 'point');
        await driver.call(
          'ext.dusk.tap',
          <String, String>{'x': '${point['x']}', 'y': '${point['y']}'},
        );
      case PerfStepVerb.drag:
        final Map<String, dynamic> from = _recorded(recorded, 'from');
        final Map<String, dynamic> to = _recorded(recorded, 'to');
        await driver.call(
          'ext.dusk.drag',
          <String, String>{
            'x': '${from['x']}',
            'y': '${from['y']}',
            'toX': '${to['x']}',
            'toY': '${to['y']}',
          },
        );
      case PerfStepVerb.wheel:
        await _wheel(_recorded(recorded, 'point'), step);
      case PerfStepVerb.pressKey:
      case PerfStepVerb.navigate:
      case PerfStepVerb.resize:
      case PerfStepVerb.wait:
        await _untargeted(step);
      case PerfStepVerb.fill:
      case PerfStepVerb.type:
      case PerfStepVerb.scroll:
        // Ruled out before the pass by _unsupportedReason.
        throw PerfRunException(
            '${step.verb.wire} cannot replay by coordinates');
    }
  }

  Future<void> _untargeted(PerfStep step) async {
    switch (step.verb) {
      case PerfStepVerb.pressKey:
        await driver.call(
          'ext.dusk.press_key',
          <String, String>{'key': step.key!, 'includeSnapshot': 'false'},
        );
      case PerfStepVerb.navigate:
        await driver.call(
          'ext.dusk.navigate',
          <String, String>{'route': step.route!, 'includeSnapshot': 'false'},
        );
      case PerfStepVerb.resize:
        await _resize(step.width!, step.height!);
      case PerfStepVerb.wait:
        await driver.pause(Duration(milliseconds: step.ms!));
      case PerfStepVerb.tap:
      case PerfStepVerb.fill:
      case PerfStepVerb.type:
      case PerfStepVerb.scroll:
      case PerfStepVerb.wheel:
      case PerfStepVerb.drag:
        throw StateError('${step.verb.wire} takes a target');
    }
  }

  /// Sends [PerfStep.ticks] wheel events at [point], one frame apart, the
  /// way a real wheel scrolls: a single large event jumps the list in one
  /// frame, and a session built on it measured five frames.
  Future<void> _wheel(Map<String, dynamic> point, PerfStep step) async {
    for (int tick = 0; tick < step.ticks; tick++) {
      if (tick > 0) await driver.pause(_kWheelTickInterval);
      await driver.cdp(
        'Input.dispatchMouseEvent',
        <String, dynamic>{
          'type': 'mouseWheel',
          'x': point['x'],
          'y': point['y'],
          'deltaX': step.dx,
          'deltaY': step.dy,
        },
      );
    }
  }

  /// Resolves [target] against the live tree in this repeat: a ref from an
  /// earlier repeat is stale after the restart.
  ///
  /// A target that is not there yet is looked up again every
  /// [_kResolvePollInterval] for up to [_kResolveBudget] (and at most
  /// [_kResolveMaxPolls] lookups) before it "matched nothing": a screen that
  /// is still building after a navigate or a tap has not drawn it yet.
  Future<String> _resolve(PerfTarget target) async {
    final Stopwatch clock = Stopwatch()..start();
    for (int poll = 1;; poll++) {
      final String? ref = await _lookup(target);
      if (ref != null) return ref;
      if (poll >= _kResolveMaxPolls || clock.elapsed >= _kResolveBudget) {
        throw PerfRunException(
          'target ${jsonEncode(target.toJson())} matched nothing on the live '
          'screen within ${_kResolveBudget.inSeconds} s ($poll lookups).',
        );
      }
      await driver.pause(_kResolvePollInterval);
    }
  }

  /// One lookup of [target]; null when nothing matches.
  ///
  /// Text, label and key go through `ext.dusk.find`, the re-resolvable
  /// handle; a text index through the list `ext.dusk.find_by_text` returns.
  /// A role goes through `ext.dusk.observe`, which lists every interactive
  /// node with the role and the merged label `dusk:snap` prints, each behind
  /// a `q<N>` handle already pinned to its own node. Scenario validation
  /// refuses an index on a label, since nothing can serve one.
  Future<String?> _lookup(PerfTarget target) async =>
      switch ((target.kind, target.index)) {
        (PerfTargetKind.text, 0) => (await driver.call(
            'ext.dusk.find',
            <String, String>{'text': target.value},
          ))['ref'] as String?,
        (PerfTargetKind.label, 0) => (await driver.call(
            'ext.dusk.find',
            <String, String>{'semanticsLabel': target.value},
          ))['ref'] as String?,
        (PerfTargetKind.key, _) => (await driver.call(
            'ext.dusk.find',
            <String, String>{'key': target.value},
          ))['ref'] as String?,
        (PerfTargetKind.text, final int index) => _at(
            await driver.call(
              'ext.dusk.find_by_text',
              <String, String>{'text': target.value},
            ),
            index,
          ),
        (PerfTargetKind.label, _) => throw StateError(
            'PerfScenario.parse refuses an index on a label target.',
          ),
        (PerfTargetKind.role, final int index) => _named(
            await driver.call(
              'ext.dusk.observe',
              <String, String>{
                'roles': target.role!,
                'includeEnrichers': 'false',
                'limit': '$_kObserveLimit',
              },
            ),
            target.value,
            index,
          ),
      };

  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, String> params,
    String where,
  ) async {
    try {
      return await driver.call(method, params);
    } on Exception catch (e) {
      throw PerfRunException('$where: $method failed: $e');
    }
  }

  /// Why the pass cannot replay [scenario] with the tree released, or null.
  String? _unsupportedReason(PerfScenario scenario) {
    for (int i = 0; i < scenario.steps.length; i++) {
      final PerfStep step = scenario.steps[i];
      if (!step.runsOn(env.platform)) continue;
      if (step.verb == PerfStepVerb.fill ||
          step.verb == PerfStepVerb.type ||
          step.verb == PerfStepVerb.scroll) {
        return 'steps[$i] (${step.verb.wire}) acts through a resolved widget, '
            'and the tree it resolves through is released during the pass; '
            'only tap, drag, wheel, press_key, navigate, resize and wait '
            'replay by coordinates.';
      }
    }
    return null;
  }

  /// Why a release that answered [answer] cannot measure the app with the
  /// tree off, naming what kept semantics on.
  ///
  /// The framework builds the tree while any handle is held, and the
  /// platform holds its own while `platformDispatcher.semanticsEnabled` is
  /// true (`heldByPlatform`). On Flutter web the engine turns that on at the
  /// first semantics update a real app sends and nothing turns it off, so
  /// once dusk has snapshotted the app it stays on.
  String _semanticsHeldReason(Map<String, dynamic> answer) {
    final String platform = env.platform.name;
    if (answer['semanticsEnabled'] != true) {
      return 'ext.dusk.semantics_hold release did not say whether the tree '
          'went off (no semanticsEnabled in ${jsonEncode(answer)}), so the '
          'app runs a dusk older than this CLI. Relaunch the app so it runs '
          'the dusk this CLI ships with.';
    }
    final String holder = switch ((answer['heldByPlatform'], env.platform)) {
      (true, PerfPlatform.chrome) => 'the platform holds it: Flutter web\'s '
          'engine turns semantics on at the first semantics tree the app '
          'sends (dusk\'s first snapshot sends one) and never turns it off, '
          'so on chrome the pass cannot measure the app with semantics off; '
          'run it on android or ios',
      (true, _) => 'the platform holds it, which on $platform means an '
          'accessibility service (a screen reader such as TalkBack or '
          'VoiceOver, or another assistive service) is on; turn it off and '
          'rerun',
      (false, _) => 'another semantics handle in the app holds it (a '
          'SemanticsHandle the app or a package took with ensureSemantics)',
      _ => 'the app did not say what holds it (no heldByPlatform), so it '
          'runs a dusk older than this CLI',
    };
    return 'on $platform, releasing dusk\'s semantics handle left semantics '
        'on: $holder.';
  }

  /// The run file for [run].
  Map<String, Object?> fileFor(
    _ScenarioRun run,
    String label, {
    String? interleavedWith,
  }) {
    final List<Map<String, dynamic>> attribution =
        run.reports[_Series.attribution]!;
    final Map<String, dynamic>? median = _medianReport(attribution);
    final bool restarts = run.scenario.setup
        .any((PerfSetupStep s) => s.verb == PerfSetupVerb.hotRestart);
    // The app knows its own renderer on web (rendererReader); the run log
    // scrape covers native, where the app answers `unknown`.
    final Object? inApp = _map(median?['env'])['renderer'];

    return <String, Object?>{
      'scenario': run.scenario.toJson(),
      'label': label,
      if (interleavedWith != null) 'interleavedWith': interleavedWith,
      'env': <String, Object?>{
        ..._map(median?['env']),
        'target': env.platform.name,
        'device': env.device,
        'emulator': env.emulator,
        'restartMode': restarts ? env.restartMode : 'none',
        'host': env.host,
        'renderer':
            inApp is String && inApp != 'unknown' ? inApp : env.renderer,
      },
      'summary': <String, Object?>{
        ...summarizePerfSeries(attribution),
        if (timing) 'timing': summarizePerfSeries(run.reports[_Series.timing]!),
      },
      'insights': _list(median?['insights']),
      'repeats': <Map<String, Object?>>[
        ..._repeats(run, _Series.attribution),
        if (timing) ..._repeats(run, _Series.timing),
      ],
      if (semanticsPass) ...<String, Object?>{
        'semanticsPass': run.unsupported == null ? 'measured' : 'unsupported',
        if (run.unsupported != null) 'semanticsPassReason': run.unsupported,
        if (run.unsupported == null)
          'semanticsOff': <String, Object?>{
            'summary': summarizePerfSeries(run.reports[_Series.semanticsOff]!),
            'repeats': _repeats(run, _Series.semanticsOff),
          },
      },
    };
  }

  List<Map<String, Object?>> _repeats(_ScenarioRun run, _Series series) =>
      <Map<String, Object?>>[
        for (final (int i, Map<String, dynamic> report)
            in run.reports[series]!.indexed)
          <String, Object?>{
            'series': series.name,
            'index': i,
            ...report,
            'resolves': run.resolves[series]![i],
          },
      ];
}

/// A target [_PerfRunner._preResolve] resolved before `perf_begin`, and the
/// hover point when its step is a wheel.
typedef _Resolved = ({String ref, Map<String, dynamic>? point});

/// One `ext.dusk.exceptions` entry as a setup failure quotes it: the type,
/// the first line of the message, cut to [_kDiagnosticMessageChars], and
/// when it happened.
String _exceptionLine(Object? entry) {
  final Map<String, dynamic> e = _map(entry);
  final String message = '${e['message'] ?? ''}'.split('\n').first;
  final String cut = message.length > _kDiagnosticMessageChars
      ? '${message.substring(0, _kDiagnosticMessageChars)}...'
      : message;
  return '${e['type']}: $cut${e['time'] == null ? '' : ' at ${e['time']}'}';
}

/// The measured report whose total per-frame count is the median, the one
/// whose insights the file carries; null when every repeat was refused.
Map<String, dynamic>? _medianReport(List<Map<String, dynamic>> reports) {
  final List<(double, Map<String, dynamic>)> measured = <(
    double,
    Map<String, dynamic>
  )>[
    for (final Map<String, dynamic> report in reports)
      if (report['refused'] != true)
        (
          perfPerFrameMetrics(report)
              .values
              .fold<double>(0, (double sum, double v) => sum + v),
          report,
        ),
  ]..sort(
      ((double, Map<String, dynamic>) x, (double, Map<String, dynamic>) y) =>
          x.$1.compareTo(y.$1),
    );
  return measured.isEmpty ? null : measured[(measured.length - 1) ~/ 2].$2;
}

/// The `--json` stdout: the file minus every `repeats[]`, insights cut to
/// the bounded report's limit, plus where the file is.
Map<String, dynamic> _stdoutShape(Map<String, Object?> file, String path) {
  final List<Object?> insights = file['insights']! as List<Object?>;
  final Object? off = file['semanticsOff'];
  return <String, dynamic>{
    for (final MapEntry<String, Object?> e in file.entries)
      if (e.key != 'repeats') e.key: e.value,
    'insights': insights.take(_kStdoutInsightLimit).toList(),
    if (insights.length > _kStdoutInsightLimit)
      'omittedInsights': insights.length - _kStdoutInsightLimit,
    if (off is Map<String, Object?>)
      'semanticsOff': <String, Object?>{'summary': off['summary']},
    'path': path,
  };
}

Map<String, dynamic> _recorded(Map<String, dynamic>? recorded, String key) {
  final Object? value = recorded?[key];
  if (value is Map<String, dynamic> && value['x'] is num && value['y'] is num) {
    return value;
  }
  throw PerfRunException(
    'no $key was recorded for this step with the tree on, so it has no '
    'coordinates to replay.',
  );
}

String? _at(Map<String, dynamic> result, int index) {
  final List<dynamic> refs = _list(result['refs']);
  return index < refs.length ? refs[index] as String? : null;
}

/// The ref of the [index]th `ext.dusk.observe` candidate labelled [name],
/// in walk order; null when there are not that many.
String? _named(Map<String, dynamic> result, String name, int index) {
  final List<String?> refs = <String?>[
    for (final Object? candidate in _list(result['candidates']))
      if (_map(candidate)['label'] == name) _map(candidate)['ref'] as String?,
  ];
  return index < refs.length ? refs[index] : null;
}

// ---------------------------------------------------------------------------
// The artisan driver
// ---------------------------------------------------------------------------

/// Drives the app through artisan's VM Service client, restarts it through
/// artisan's own commands, and reaches Chrome through [CdpClient].
final class _ArtisanPerfRunDriver implements PerfRunDriver {
  _ArtisanPerfRunDriver(
    this._client, {
    required this.cdpPort,
    required this.relaunch,
    required this.profileStatic,
  });

  final int? cdpPort;
  final bool relaunch;
  final bool profileStatic;

  VmServiceClient _client;

  /// False for the dispatcher's client, which is not ours to close; true for
  /// one opened after a relaunch.
  bool _ownsClient = false;
  CdpClient? _cdp;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    final String isolateId = await _client.getMainIsolateId();
    return _client.callServiceExtension<Map<String, dynamic>>(
      method,
      isolateId: isolateId,
      params: params,
    );
  }

  @override
  Future<Map<String, dynamic>> cdp(
    String method, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final int? port = cdpPort;
    if (port == null) {
      throw PerfRunException('$method needs Chrome DevTools, and this '
          'session has no CDP port.');
    }
    final CdpClient client = _cdp ??= await CdpClient.connect(port: port);
    return client.send(method, params);
  }

  @override
  Future<void> restart() async {
    final BufferedOutput output = BufferedOutput();

    // 1. A debug build hot restarts in place; wait for a NEW boot id. Not a
    //    new isolate: DWDS keeps isolate "1" across a web hot restart, and on
    //    the VM the old isolate keeps answering until the new one replaces it.
    if (!relaunch) {
      final String before;
      try {
        before = await readDuskBootId(_client);
      } on Exception catch (e) {
        throw PerfRunException(
          'the app does not answer ext.dusk.boot_id ($e), so a restart '
          'cannot be told apart from the app before it. Relaunch the app so '
          'it runs the dusk this CLI ships with.',
        );
      }
      final int code = await HotRestartCommand().handle(
        ArtisanContext.bare(MapInput(const <String, dynamic>{}), output),
      );
      if (code != 0) {
        throw PerfRunException('hot restart failed: ${output.content.trim()}');
      }
      await awaitDuskBoot(
        _client,
        replacing: before,
        timeout: _kHotRestartTimeout,
      );
      return;
    }

    // 2. A profile build cannot hot restart: relaunch through the runner,
    //    which carries the session's flags, and reconnect to the new VM.
    await _cdp?.close();
    _cdp = null;
    final int code = await RestartCommand().handle(
      ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'profile-static': profileStatic,
          'timeout': '${_kRelaunchTimeout.inSeconds}',
        }),
        output,
      ),
    );
    if (code != 0) {
      throw PerfRunException('relaunch failed: ${output.content.trim()}');
    }
    final String? uri = (await StateFile.read())?['vmServiceUri'] as String?;
    if (uri == null) {
      throw PerfRunException('the relaunch recorded no VM Service URI.');
    }
    if (_ownsClient) await _client.disconnect();
    _client = VmServiceClient(uri);
    await _client.connect();
    _ownsClient = true;
    await awaitDuskBoot(_client, replacing: null, timeout: _kRelaunchTimeout);
  }

  @override
  Future<void> pause(Duration duration) => Future<void>.delayed(duration);

  @override
  Future<void> close() async {
    await _cdp?.close();
    _cdp = null;
    if (_ownsClient) await _client.disconnect();
  }
}

/// The boot id the running app's `DuskPlugin.install()` minted, read from
/// `ext.dusk.boot_id` on the main isolate.
///
/// Throws whatever the VM Service throws when the extension does not answer:
/// an RPC error while the app restarts, or on an app built with a dusk older
/// than this one.
@visibleForTesting
Future<String> readDuskBootId(VmServiceClient client) async {
  final String isolateId = await client.getMainIsolateId();
  final Map<String, dynamic> result =
      await client.callServiceExtension<Map<String, dynamic>>(
    'ext.dusk.boot_id',
    isolateId: isolateId,
  );
  return result['bootId'] as String;
}

/// Polls until `ext.dusk.boot_id` answers with an id other than [replacing]
/// (any id when [replacing] is null, after a relaunch), which is when
/// `main()` has run `DuskPlugin.install()` again. The boot id registers last,
/// so every other `ext.dusk.*` answers by then.
///
/// The isolate id proves nothing: DWDS keeps `"1"` across a web hot restart.
/// While the app restarts the extension answers with errors (DWDS -32603 for
/// one not registered yet, no isolate, an isolate going away); those are the
/// state being waited out, retried every [pollInterval] until [timeout], and
/// the last one is named when it runs out. A read that hangs is cut at the
/// time left, so [timeout] holds.
@visibleForTesting
Future<void> awaitDuskBoot(
  VmServiceClient client, {
  required String? replacing,
  required Duration timeout,
  Duration pollInterval = _kBootPollInterval,
}) async {
  final Stopwatch clock = Stopwatch()..start();
  Object? last;
  while (clock.elapsed < timeout) {
    try {
      final String id =
          await readDuskBootId(client).timeout(timeout - clock.elapsed);
      if (id != replacing) return;
      last = null;
    } on Exception catch (e) {
      last = e;
    } on StateError catch (e) {
      last = e;
    }
    await Future<void>.delayed(pollInterval);
  }
  throw PerfRunException(
    'the app did not come back within ${timeout.inSeconds} s of the restart'
    '${last == null ? '' : ' (last answer: $last)'}.',
  );
}

Future<Map<String, Object?>> _hostInfo() async {
  Future<String?> firstLine(String executable, List<String> args) async {
    final ProcessResult result = await Process.run(executable, args);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
  }

  final String? cpu = Platform.isMacOS
      ? await firstLine('sysctl', <String>['-n', 'machdep.cpu.brand_string'])
      : Platform.isLinux
          ? RegExp(r'^model name\s*:\s*(.+)$', multiLine: true)
              .firstMatch(await File('/proc/cpuinfo').readAsString())
              ?.group(1)
          : null;
  return <String, Object?>{
    'os': Platform.operatingSystem,
    'uname': Platform.isWindows
        ? Platform.operatingSystemVersion
        : await firstLine('uname', <String>['-srm']),
    'cpu': cpu,
    'cores': Platform.numberOfProcessors,
  };
}

/// The artisan run log beside the session's state file, else the global
/// one, as `artisan logs` reads it; null when neither exists.
Future<String?> _runLog() async {
  for (final File log in <File>[
    File('${File(StateFile.path).parent.path}/flutter-dev.log'),
    File('${StateFile.homeDir}/flutter-dev.log'),
  ]) {
    if (log.existsSync()) return log.readAsString();
  }
  return null;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// The path of a route or a router URI, `/` when it has none.
String _routePath(String route) {
  final String path = Uri.tryParse(route)?.path ?? route;
  return path.isEmpty ? '/' : path;
}

/// An iOS simulator UDID; a physical device's id has a different shape.
final RegExp _kSimulatorUdid = RegExp(
  r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
);

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<dynamic> _list(Object? value) =>
    value is List<dynamic> ? value : const <dynamic>[];

num _num(Object? value) => value is num ? value : 0;

/// An int when the value is whole, so a median of frame counts reads `42`.
num _plain(double value) =>
    value == value.roundToDouble() ? value.toInt() : _round(value, 4);

double _round(double value, int places) {
  final num factor = <int>[1, 10, 100, 1000, 10000][places];
  return (value * factor).roundToDouble() / factor;
}

double _min(double x, double y) => x < y ? x : y;

double _max(double x, double y) => x > y ? x : y;

/// CLI options arrive as strings, MCP arguments as typed JSON.
int? _readInt(Object? raw) => switch (raw) {
      final int value => value,
      final String value => int.tryParse(value),
      _ => null,
    };

bool _readBool(Object? raw) => switch (raw) {
      final bool value => value,
      final String value => value == 'true' || value == '1',
      _ => false,
    };
