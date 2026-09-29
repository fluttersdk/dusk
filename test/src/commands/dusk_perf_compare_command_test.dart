import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_compare_command.dart';

/// A run file as `dusk:perf_run` writes it, reduced to what the compare
/// reads.
Map<String, Object?> _run({
  int painted = 100,
  Map<String, double> perFrame = const <String, double>{
    'blocks.MonitorRow': 2.0,
    'wind.wDivBuilds': 30.0,
  },
  Map<String, Object?> spread = const <String, Object?>{},
  Map<String, double>? timingMs,
  Map<String, double> attributionMs = const <String, double>{
    'buildMs.p50': 4.0,
  },
  Map<String, Object?> env = const <String, Object?>{'emulator': false},
  Map<String, Object?>? thresholds,
  int repeats = 3,
  String name = 'list',
}) {
  return <String, Object?>{
    'scenario': <String, Object?>{
      'name': name,
      if (thresholds != null) 'thresholds': thresholds,
    },
    'label': 'x',
    'env': env,
    'summary': <String, Object?>{
      'repeats': repeats,
      'refused': 0,
      if (repeats > 0) ...<String, Object?>{
        'frames': <String, Object?>{'painted': painted},
        'perFrame': perFrame,
        'ms': attributionMs,
        'spread': <String, Object?>{'perFrame': spread},
      },
      if (timingMs != null)
        'timing': <String, Object?>{
          'repeats': 3,
          'refused': 0,
          'ms': timingMs,
          'spread': <String, Object?>{'ms': <String, Object?>{}},
        },
    },
  };
}

Map<String, Object?> _row(Map<String, Object?> result, String metric) =>
    (result['rows']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((Map<String, Object?> r) => r['metric'] == metric);

void main() {
  group('comparePerfRuns()', () {
    test('10% fewer frames with identical per-frame counts is unchanged', () {
      // Raw counts fall 10% with the frames; per painted frame nothing moved.
      // Reading the raw counts would call this an improvement.
      final Map<String, Object?> result = comparePerfRuns(
        _run(painted: 100),
        _run(painted: 90),
      );

      expect(result['verdict'], 'unchanged');
      expect(result['verdict'], isNot('improved'));
      expect(
        (result['frames']! as Map<String, Object?>)['painted'],
        <String, Object?>{'a': 100, 'b': 90},
      );
    });

    test('a per-frame count 30% up is an error-level regression', () {
      final Map<String, Object?> result = comparePerfRuns(
        _run(),
        _run(perFrame: <String, double>{
          'blocks.MonitorRow': 2.6,
          'wind.wDivBuilds': 30.0,
        }),
      );

      expect(result['verdict'], 'regressed');
      final Map<String, Object?> row = _row(result, 'blocks.MonitorRow');
      expect(row['verdict'], 'regressed');
      expect(row['severity'], 'error');
      expect(row['deltaPct'], 30.0);
      expect(result['unchanged'], 1);
    });

    test('12% up is a warning, 15% down an improvement', () {
      final Map<String, Object?> warn = comparePerfRuns(
        _run(),
        _run(perFrame: <String, double>{
          'blocks.MonitorRow': 2.24,
          'wind.wDivBuilds': 30.0,
        }),
      );
      final Map<String, Object?> better = comparePerfRuns(
        _run(),
        _run(perFrame: <String, double>{
          'blocks.MonitorRow': 1.7,
          'wind.wDivBuilds': 30.0,
        }),
      );

      expect(_row(warn, 'blocks.MonitorRow')['severity'], 'warn');
      expect(warn['verdict'], 'regressed');
      expect(better['verdict'], 'improved');
      expect(_row(better, 'blocks.MonitorRow')['verdict'], 'improved');
    });

    test('a change inside the repeats\' own spread is unchanged', () {
      final Map<String, Object?> result = comparePerfRuns(
        _run(spread: <String, Object?>{
          'blocks.MonitorRow': <String, Object?>{'min': 1.6, 'max': 2.5},
        }),
        _run(perFrame: <String, double>{
          'blocks.MonitorRow': 2.4,
          'wind.wDivBuilds': 30.0,
        }),
      );

      expect(result['verdict'], 'unchanged');
    });

    test('a metric absent from A is a new, warn-level regression', () {
      final Map<String, Object?> result = comparePerfRuns(
        _run(),
        _run(perFrame: <String, double>{
          'blocks.MonitorRow': 2.0,
          'wind.wDivBuilds': 30.0,
          'blocks.Spinner': 1.0,
        }),
      );

      final Map<String, Object?> row = _row(result, 'blocks.Spinner');
      expect(row['verdict'], 'regressed');
      expect(row['severity'], 'warn');
      expect(row['deltaPct'], isNull);
    });

    test('ms are gated only from timing-mode medians', () {
      // Attribution ms tripled, but attribution ms are inflated by the
      // profiling and never compared.
      final Map<String, Object?> noTiming = comparePerfRuns(
        _run(),
        _run(attributionMs: <String, double>{'buildMs.p50': 12.0}),
      );
      expect(noTiming['verdict'], 'unchanged');
      expect(
        (noTiming['timing']! as Map<String, Object?>)['gated'],
        isFalse,
      );

      final Map<String, Object?> timed = comparePerfRuns(
        _run(timingMs: <String, double>{'buildMs.p50': 4.0}),
        _run(timingMs: <String, double>{'buildMs.p50': 5.2}),
      );
      expect(timed['verdict'], 'regressed');
      expect(_row(timed, 'timing.buildMs.p50')['severity'], 'error');
    });

    test('emulator raster ms are info only', () {
      final Map<String, Object?> result = comparePerfRuns(
        _run(
          timingMs: <String, double>{'rasterMs.p50': 3.0},
          env: const <String, Object?>{'emulator': true},
        ),
        _run(
          timingMs: <String, double>{'rasterMs.p50': 9.0},
          env: const <String, Object?>{'emulator': true},
        ),
      );

      expect(result['verdict'], 'unchanged');
      expect(_row(result, 'timing.rasterMs.p50')['severity'], 'info');
    });

    test('a scenario threshold overrides the defaults', () {
      final Map<String, Object?> result = comparePerfRuns(
        _run(),
        _run(
          perFrame: <String, double>{
            'blocks.MonitorRow': 2.1,
            'wind.wDivBuilds': 30.0,
          },
          thresholds: <String, Object?>{'warn': 2, 'error': 4},
        ),
      );

      expect(_row(result, 'blocks.MonitorRow')['severity'], 'error');
      expect(
        result['thresholds'],
        <String, Object?>{'warn': 2, 'error': 4},
      );
    });

    test(
      'wind.cacheHits rising and wind.cacheMisses falling reads improved '
      'or unchanged, never regressed',
      () {
        final Map<String, Object?> result = comparePerfRuns(
          _run(
            perFrame: <String, double>{
              'blocks.MonitorRow': 2.0,
              'wind.wDivBuilds': 30.0,
              'wind.cacheHits': 20.0,
              'wind.cacheMisses': 10.0,
            },
          ),
          _run(
            perFrame: <String, double>{
              'blocks.MonitorRow': 2.0,
              'wind.wDivBuilds': 30.0,
              'wind.cacheHits': 29.0,
              'wind.cacheMisses': 1.0,
            },
          ),
        );

        expect(result['verdict'], isNot('regressed'));
        final Map<String, Object?> hits = _row(result, 'wind.cacheHits');
        expect(hits['verdict'], isNot('regressed'));
        final Map<String, Object?> misses = _row(result, 'wind.cacheMisses');
        expect(misses['verdict'], isNot('regressed'));
      },
    );

    test(
      'an info row appears when scenario name, env.target or env.buildMode '
      'differ, and it never gates the verdict',
      () {
        final Map<String, Object?> result = comparePerfRuns(
          _run(
            name: 'list',
            env: const <String, Object?>{
              'emulator': false,
              'target': 'ios',
              'buildMode': 'profile',
            },
          ),
          _run(
            name: 'detail',
            env: const <String, Object?>{
              'emulator': false,
              'target': 'android',
              'buildMode': 'debug',
            },
          ),
        );

        expect(_row(result, 'scenario.name')['severity'], 'info');
        expect(_row(result, 'env.target')['severity'], 'info');
        expect(_row(result, 'env.buildMode')['severity'], 'info');
        expect(result['verdict'], isNot('regressed'));
      },
    );

    test('a run with no measured repeat cannot be compared', () {
      expect(
        () => comparePerfRuns(_run(repeats: 0), _run()),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DuskPerfCompareCommand', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('dusk_perf_compare_test_');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    Future<String> write(String name, Map<String, Object?> run) async {
      final File file = File('${temp.path}/$name.json');
      await file.writeAsString(jsonEncode(run));
      return file.path;
    }

    Future<(int, String)> compare(Map<String, dynamic> options) async {
      final BufferedOutput output = BufferedOutput();
      final int code = await DuskPerfCompareCommand().handle(
        ArtisanContext.bare(MapInput(options), output),
      );
      return (code, output.content);
    }

    test('name is dusk:perf_compare and boot is none', () {
      expect(DuskPerfCompareCommand().name, 'dusk:perf_compare');
      expect(DuskPerfCompareCommand().boot, CommandBoot.none);
    });

    test('prints a compact table with the verdict and exits 0', () async {
      final String a = await write('a', _run());
      final String b = await write('b', _run(painted: 90));

      final (int code, String out) =
          await compare(<String, dynamic>{'a': a, 'b': b});

      expect(code, 0);
      expect(out, contains('unchanged'));
      expect(out, contains('100'));
      expect(out, contains('90'));
    });

    test('an error-level regression exits 1 and --json prints the result',
        () async {
      final String a = await write('a', _run());
      final String b = await write(
        'b',
        _run(perFrame: <String, double>{
          'blocks.MonitorRow': 3.0,
          'wind.wDivBuilds': 30.0,
        }),
      );

      final (int code, String out) =
          await compare(<String, dynamic>{'a': a, 'b': b, 'json': true});

      expect(code, 1);
      final Map<String, dynamic> result =
          jsonDecode(out.trim()) as Map<String, dynamic>;
      expect(result['verdict'], 'regressed');
    });

    test('a missing file or argument exits 1', () async {
      final String a = await write('a', _run());

      final (int missing, _) = await compare(<String, dynamic>{'a': a});
      final (int absent, String out) = await compare(
        <String, dynamic>{'a': a, 'b': '${temp.path}/nope.json'},
      );

      expect(missing, 1);
      expect(absent, 1);
      expect(out, contains('nope.json'));
    });

    test('a run whose every repeat refused exits 1', () async {
      final String a = await write('a', _run(repeats: 0));
      final String b = await write('b', _run());

      final (int code, String out) =
          await compare(<String, dynamic>{'a': a, 'b': b});

      expect(code, 1);
      expect(out, contains('refused'));
    });
  });
}
