/// The campaign `dusk:perf_campaign` runs: a YAML file naming the scenarios,
/// two shell hooks, the Android preparation, the setup to run after each cold
/// start and how many times a failed scenario is retried, validated whole
/// before anything runs.
///
/// Pure Dart with no Flutter import, like `scenario.dart`, whose loaders read
/// the scenarios and the `after_start` setup so both share one interpolation
/// and one secret taint.
///
/// ```yaml
/// scenarios:                      # relative to this file; `*` in the file name only
///   - scenarios/*.yaml
/// hooks:                          # shell strings, never interpolated
///   before_campaign: ./services.sh up
///   before_scenario: ./services.sh reset
/// android:
///   avd: uptizm_pixel8_api35
///   reverse: [8001, 8080]
///   grant: [android.permission.POST_NOTIFICATIONS]
/// after_start:                    # the scenario `setup` grammar, includes and all
///   - include: fragments/login.yaml
///     with: {password: "${env.DEMO_PASSWORD}"}
/// retries: 1                      # default 1
/// ```
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'scenario.dart';

/// A campaign that failed validation, with every problem found rather than
/// the first. A sibling of [PerfScenarioException] so the header a command
/// prints names the campaign, not a scenario.
final class PerfCampaignException implements Exception {
  PerfCampaignException(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'Invalid perf campaign:\n${problems.map((String p) => '- $p').join('\n')}';
}

/// Shell strings the command runs verbatim through `/bin/sh -c`.
final class PerfHooks {
  const PerfHooks({this.beforeCampaign, this.beforeScenario});

  final String? beforeCampaign;
  final String? beforeScenario;
}

/// What the command prepares on an Android emulator before the first start.
final class PerfAndroid {
  const PerfAndroid({
    this.avd,
    this.reverse = const <int>[],
    this.grant = const <String>[],
  });

  /// The emulator to boot; null leaves the choice to the command.
  final String? avd;

  /// TCP ports `adb reverse` exposes from the host.
  final List<int> reverse;

  /// Permissions `pm grant` gives the app after it is installed.
  final List<String> grant;
}

/// One scenario of the expanded list: a file with `variants` is several.
final class PerfCampaignScenario {
  const PerfCampaignScenario({required this.path, required this.scenario});

  /// The absolute path of the file to hand `dusk:perf_run`.
  final String path;

  final PerfScenario scenario;

  /// The `variants:` key of [path] this scenario came from, for
  /// `dusk:perf_run --variant`; null when the file has none.
  String? get variant => scenario.variant;

  Set<PerfPlatform> get platforms => scenario.platforms;
}

/// A validated campaign.
final class PerfCampaign {
  const PerfCampaign({
    required this.scenarios,
    required this.afterStart,
    required this.secrets,
    this.hooks = const PerfHooks(),
    this.android = const PerfAndroid(),
    this.retries = 1,
  });

  /// Every scenario, variants expanded, in the order the campaign lists them.
  final List<PerfCampaignScenario> scenarios;

  /// Runs after every cold start, before the scenario's own setup.
  final List<PerfSetupStep> afterStart;

  /// Every tainted value read while loading the scenarios and [afterStart],
  /// for the command to build its redactor from.
  final Set<String> secrets;

  final PerfHooks hooks;
  final PerfAndroid android;

  /// Extra attempts after a scenario fails.
  final int retries;
}

/// Loads the campaign at [path].
///
/// `scenarios` is a list of paths relative to the campaign file, where a
/// `*` in the file name (never in a directory, never `**`) expands against
/// that directory, sorted. `after_start` is read by [loadPerfSetup] and each
/// scenario file by [loadPerfScenarios], both against [env]; a hook is never
/// interpolated, because it runs in a shell that reads `$NAME` itself.
///
/// Throws [PerfCampaignException] listing every problem, those of each
/// scenario file prefixed with the file, and the [FileSystemException] of a
/// campaign file it cannot read.
Future<PerfCampaign> loadPerfCampaign(
  String path, {
  Map<String, String> env = const <String, String>{},
}) async {
  final String file = _absolutePath(path);
  final Map<Object?, Object?> document =
      _campaignDocument(await File(file).readAsString());
  return _CampaignReader(file: file, env: env).read(document);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

const Set<String> _kCampaignKeys = <String>{
  'scenarios',
  'hooks',
  'android',
  'after_start',
  'retries',
};
const Set<String> _kHookKeys = <String>{'before_campaign', 'before_scenario'};
const Set<String> _kAndroidKeys = <String>{'avd', 'reverse', 'grant'};

const int _kDefaultRetries = 1;

String _absolutePath(String path) =>
    Uri.file(File(path).absolute.path).normalizePath().toFilePath();

Map<Object?, Object?> _campaignDocument(String source) {
  final Object? document;
  try {
    document = loadYaml(source);
  } on YamlException catch (e) {
    throw PerfCampaignException(<String>['not valid YAML: ${e.message}']);
  }
  if (document is! Map<Object?, Object?>) {
    throw PerfCampaignException(<String>[
      'the campaign must be a map of ${_kCampaignKeys.join(', ')}.',
    ]);
  }
  return document;
}

/// Reads a campaign document into the model, collecting every problem.
final class _CampaignReader {
  _CampaignReader({required this.file, required this.env});

  /// The absolute path of the campaign file.
  final String file;

  final Map<String, String> env;

  final List<String> problems = <String>[];
  final Set<String> secrets = <String>{};

  Future<PerfCampaign> read(Map<Object?, Object?> document) async {
    // 1. Keys nothing reads.
    for (final Object? key in document.keys) {
      if (!_kCampaignKeys.contains(key)) {
        problems.add('unknown key "$key"; allowed: '
            '${_kCampaignKeys.join(', ')}.');
      }
    }

    // 2. Each section on its own, so one edit fixes them all. `after_start`
    //    goes to the loader as `loadYaml` answered it: the loader
    //    interpolates it, once.
    final List<PerfCampaignScenario> scenarios =
        await _scenarios(document['scenarios']);
    final PerfHooks hooks = _hooks(document['hooks']);
    final PerfAndroid android = _android(document['android']);
    final int retries = _retries(document['retries']);
    final List<PerfSetupStep> afterStart = _afterStart(document['after_start']);

    if (problems.isNotEmpty) throw PerfCampaignException(problems);
    return PerfCampaign(
      scenarios: scenarios,
      afterStart: afterStart,
      secrets: Set<String>.unmodifiable(secrets),
      hooks: hooks,
      android: android,
      retries: retries,
    );
  }

  Future<List<PerfCampaignScenario>> _scenarios(Object? raw) async {
    if (raw is! List<Object?> || raw.isEmpty) {
      problems.add('scenarios must be a non-empty list of scenario paths.');
      return const <PerfCampaignScenario>[];
    }

    // 1. Every entry to the files it names, before any file is read.
    final List<String> files = <String>[];
    for (final (int i, Object? entry) in raw.indexed) {
      if (entry is! String || entry.isEmpty) {
        problems.add('scenarios[$i] must be a non-empty path (got $entry).');
        continue;
      }
      files.addAll(_expand(entry, 'scenarios[$i]'));
    }

    // 2. Each file's scenarios, every file's problems kept: one broken file
    //    must not hide the next.
    final List<PerfCampaignScenario> scenarios = <PerfCampaignScenario>[];
    final Map<String, String> owner = <String, String>{};
    for (final String path in files) {
      final String shown = _shown(path);
      final PerfLoadResult loaded;
      try {
        loaded = await loadPerfScenarios(path, env: env);
      } on PerfScenarioException catch (e) {
        problems
            .addAll(<String>[for (final String p in e.problems) '$shown: $p']);
        continue;
      } on FileSystemException catch (e) {
        problems
            .add('$shown: cannot read (${e.osError?.message ?? e.message}).');
        continue;
      }
      secrets.addAll(loaded.secrets);

      // 3. A name is the run file's stem, so two files sharing one would
      //    overwrite each other.
      for (final PerfScenario scenario in loaded.scenarios) {
        final String? first = owner[scenario.name];
        if (first != null) {
          problems.add('duplicate scenario name "${scenario.name}" in '
              '$first and $shown: each name is a run file.');
          continue;
        }
        owner[scenario.name] = shown;
        scenarios.add(PerfCampaignScenario(path: path, scenario: scenario));
      }
    }
    return scenarios;
  }

  /// The absolute paths [entry] names: itself, or the files of its directory
  /// its basename glob matches, sorted.
  List<String> _expand(String entry, String at) {
    final List<String> parts = entry.split('/');
    final String basename = parts.removeLast();
    if (parts.any((String part) => part.contains('*')) ||
        basename.contains('**')) {
      problems.add('$at: "$entry" may hold a * in the file name only, never '
          'in a directory and never as **.');
      return const <String>[];
    }

    final String resolved =
        Uri.file(file).resolveUri(Uri.file(entry)).toFilePath();
    if (!basename.contains('*')) {
      if (File(resolved).existsSync()) return <String>[resolved];
      problems.add('$at: "$entry" is not a file.');
      return const <String>[];
    }

    final Directory directory = File(resolved).parent;
    final RegExp glob = RegExp(
      '^${basename.split('*').map(RegExp.escape).join('[^/]*')}\$',
    );
    final List<String> matches = !directory.existsSync()
        ? <String>[]
        : <String>[
            for (final File match in directory.listSync().whereType<File>())
              if (glob.hasMatch(match.uri.pathSegments.last)) match.path,
          ]
      ..sort();
    if (matches.isEmpty) problems.add('$at: "$entry" matches no file.');
    return matches;
  }

  PerfHooks _hooks(Object? raw) {
    if (raw == null) return const PerfHooks();
    if (raw is! Map<Object?, Object?>) {
      problems.add('hooks must be a map of ${_kHookKeys.join(', ')}.');
      return const PerfHooks();
    }
    _unknownKeys(raw, _kHookKeys, 'hooks');
    return PerfHooks(
      beforeCampaign: _hook(raw['before_campaign'], 'hooks.before_campaign'),
      beforeScenario: _hook(raw['before_scenario'], 'hooks.before_scenario'),
    );
  }

  String? _hook(Object? raw, String at) {
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      problems.add('$at must be a non-empty shell string.');
      return null;
    }
    // A hook is never echoed: it is the one string a secret could be
    // spliced into by hand.
    if (raw.contains(r'${')) {
      problems.add('$at holds a "\${": hooks run in a shell; read the '
          r'variable there as $NAME.');
      return null;
    }
    return raw;
  }

  PerfAndroid _android(Object? raw) {
    if (raw == null) return const PerfAndroid();
    if (raw is! Map<Object?, Object?>) {
      problems.add('android must be a map of ${_kAndroidKeys.join(', ')}.');
      return const PerfAndroid();
    }
    _unknownKeys(raw, _kAndroidKeys, 'android');

    final Object? avd = raw['avd'];
    if (avd != null && (avd is! String || avd.isEmpty)) {
      problems.add('android.avd must be a non-empty string.');
    }
    return PerfAndroid(
      avd: avd is String && avd.isNotEmpty ? avd : null,
      reverse: _list(raw['reverse'], 'android.reverse', _port),
      grant: _list(raw['grant'], 'android.grant', _permission),
    );
  }

  int? _port(Object? raw, String at) {
    if (raw is int && raw >= 1 && raw <= 65535) return raw;
    problems.add('$at must be a port, 1 to 65535 (got $raw).');
    return null;
  }

  String? _permission(Object? raw, String at) {
    if (raw is String && raw.isNotEmpty) return raw;
    problems.add('$at must be a non-empty string.');
    return null;
  }

  /// [raw] as a list read entry by entry with [read]; an entry that fails
  /// is reported and left out.
  List<T> _list<T>(Object? raw, String at, T? Function(Object?, String) read) {
    if (raw == null) return <T>[];
    if (raw is! List<Object?>) {
      problems.add('$at must be a list.');
      return <T>[];
    }
    return <T>[
      for (final (int i, Object? value) in raw.indexed)
        if (read(value, '$at[$i]') case final T item) item,
    ];
  }

  int _retries(Object? raw) {
    if (raw == null) return _kDefaultRetries;
    if (raw is int && raw >= 0) return raw;
    problems.add('retries must be a non-negative integer (got $raw).');
    return _kDefaultRetries;
  }

  List<PerfSetupStep> _afterStart(Object? raw) {
    try {
      final PerfSetupLoadResult loaded = loadPerfSetup(
        raw,
        path: file,
        at: 'after_start',
        env: env,
      );
      secrets.addAll(loaded.secrets);
      return loaded.setup;
    } on PerfScenarioException catch (e) {
      problems.addAll(e.problems);
      return const <PerfSetupStep>[];
    }
  }

  void _unknownKeys(Map<Object?, Object?> map, Set<String> allowed, String at) {
    for (final Object? key in map.keys) {
      if (!allowed.contains(key)) {
        problems.add('$at: unknown key "$key"; allowed: '
            '${allowed.join(', ')}.');
      }
    }
  }

  /// [target] as problems show it: relative to the campaign's directory when
  /// under it.
  String _shown(String target) {
    final String dir = File(file).parent.path;
    final String prefix = dir.endsWith(Platform.pathSeparator)
        ? dir
        : '$dir${Platform.pathSeparator}';
    return target.startsWith(prefix) ? target.substring(prefix.length) : target;
  }
}
