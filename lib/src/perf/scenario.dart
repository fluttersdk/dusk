/// The scenario `dusk:perf_run` drives: a YAML file naming the setup, the
/// steps and how often to repeat them, validated whole before anything runs.
///
/// Pure Dart with no Flutter import, because the CLI wrapper that loads it
/// (`bin/fluttersdk_dusk.dart`) has to stay Flutter-free.
///
/// ```yaml
/// name: monitors-list-scroll-1440
/// viewport: {width: 1440, height: 900}      # chrome only
/// platforms: [chrome, android]               # default: all three
/// setup:
///   - hot_restart
///   - navigate: /monitors
///   - wait_for_text: Monitors                # or {text: Monitors, timeout_ms: 20000}
///   - wait_for_network_idle
///   - tap: {target: {text: perf-monitor-0000}}   # a gesture, unmeasured
/// steps:
///   - wheel: {target: {key: monitor-list}, dy: 1200}
///     only: [chrome]
///   - drag: {target: {text: Monitors}, dy: -600}
///     only: [android, ios]
///   - tap: {target: {role: button, name: Add monitor}}
///   - wait: 400
/// repeat: 3
/// thresholds: {warn: 10, error: 25}          # percent, per metric
/// ```
library;

import 'package:yaml/yaml.dart';

/// Where a scenario can run.
enum PerfPlatform {
  chrome,
  android,
  ios;

  static PerfPlatform? tryParse(Object? name) =>
      name is String ? PerfPlatform.values.asNameMap()[name] : null;
}

/// Which `dusk:find` predicate a target maps to.
enum PerfTargetKind {
  /// `{text: ...}`: `dusk:find --text`.
  text,

  /// `{label: ...}`: `dusk:find --semanticsLabel`.
  label,

  /// `{role: ..., name: ...}`: the node `dusk:snap` prints as that role
  /// and name, listed through `ext.dusk.observe`.
  role,

  /// `{key: ...}`: `dusk:find --key`.
  key,
}

/// What a setup entry does before every repeat.
enum PerfSetupVerb {
  navigate('navigate'),

  /// A hot restart on debug; a full relaunch through the runner on a build
  /// that cannot hot restart.
  hotRestart('hot_restart'),
  waitForText('wait_for_text'),
  waitForNetworkIdle('wait_for_network_idle'),

  /// One of [kPerfSetupGestures], written with the steps' own grammar and
  /// carried in [PerfSetupStep.gesture]. Its wire is never read from YAML:
  /// the entry is spelled with the gesture's verb.
  gesture('gesture');

  const PerfSetupVerb(this.wire);

  /// The spelling in the YAML.
  final String wire;

  static PerfSetupVerb? tryParse(String wire) {
    for (final PerfSetupVerb verb in values) {
      if (verb != gesture && verb.wire == wire) return verb;
    }
    return null;
  }
}

/// What a step does inside the measured window.
enum PerfStepVerb {
  tap('tap'),
  fill('fill'),
  type('type'),
  pressKey('press_key'),
  scroll('scroll'),

  /// A CDP `Input.dispatchMouseEvent` mouseWheel. Chrome only.
  wheel('wheel'),
  drag('drag'),
  navigate('navigate'),

  /// A CDP viewport change. Chrome only.
  resize('resize'),
  wait('wait');

  const PerfStepVerb(this.wire);

  final String wire;

  /// Whether the step acts on a widget named by a target.
  bool get takesTarget => switch (this) {
        tap || fill || type || scroll || wheel || drag => true,
        pressKey || navigate || resize || wait => false,
      };

  /// Whether the step drives Chrome DevTools, which only the browser has.
  bool get chromeOnly => this == wheel || this == resize;

  static PerfStepVerb? tryParse(String wire) {
    for (final PerfStepVerb verb in values) {
      if (verb.wire == wire) return verb;
    }
    return null;
  }
}

/// The `role` values a `{role, name}` target accepts: the roles `dusk:snap`
/// prints and `ext.dusk.observe` filters on.
const Set<String> kPerfTargetRoles = <String>{
  'button',
  'textbox',
  'checkbox',
  'link',
  'heading',
  'image',
};

/// The step verbs a `setup` entry may use. They run before `perf_begin`, so
/// the path to the measured screen (a row tapped, a field filled) is not
/// measured. `navigate` is a setup verb of its own; `scroll` and `resize`
/// are left to the steps, and the viewport to `viewport`.
const Set<PerfStepVerb> kPerfSetupGestures = <PerfStepVerb>{
  PerfStepVerb.tap,
  PerfStepVerb.fill,
  PerfStepVerb.type,
  PerfStepVerb.pressKey,
  PerfStepVerb.wheel,
  PerfStepVerb.drag,
  PerfStepVerb.wait,
};

/// Timeout for `wait_for_text` when the setup entry names none. A hot restart
/// on Flutter web recompiles, so the first text can take several seconds.
const int kPerfWaitForTextTimeoutMs = 15000;

/// The most events one `wheel` step may send: at one frame apart, 200 ticks
/// is about three seconds of scrolling, longer than any single gesture.
const int _kMaxWheelTicks = 200;

/// Whether [name] may become part of a file name: `[a-z0-9_-]` only, which
/// also rules out `/`, `..` and an empty string.
bool isSafePerfName(String name) => RegExp(r'^[a-z0-9_-]+$').hasMatch(name);

/// A scenario that failed validation, with every problem found rather than
/// the first, so one edit fixes the file.
final class PerfScenarioException implements Exception {
  PerfScenarioException(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'Invalid perf scenario:\n${problems.map((String p) => '- $p').join('\n')}';
}

/// The widget a step acts on, resolved against the live tree right before
/// the step runs. Never a ref: an `e<N>` or `q<N>` minted by one run is stale
/// after the next navigate.
final class PerfTarget {
  const PerfTarget({
    required this.kind,
    required this.value,
    this.role,
    this.index = 0,
  });

  final PerfTargetKind kind;

  /// The text, label or key; for [PerfTargetKind.role], the name.
  final String value;

  /// The role flag, set only for [PerfTargetKind.role].
  final String? role;

  /// Which of the matching nodes, from zero in walk order.
  final int index;

  Map<String, Object?> toJson() => <String, Object?>{
        if (kind == PerfTargetKind.role) ...<String, Object?>{
          'role': role,
          'name': value,
        } else
          kind.name: value,
        if (index != 0) 'index': index,
      };
}

/// One setup entry.
final class PerfSetupStep {
  const PerfSetupStep(this.verb, {this.argument, this.timeoutMs})
      : gesture = null;

  /// A gesture from the steps' grammar, run unmeasured before the window.
  const PerfSetupStep.gesture(PerfStep this.gesture)
      : verb = PerfSetupVerb.gesture,
        argument = null,
        timeoutMs = null;

  final PerfSetupVerb verb;

  /// The gesture, set only for [PerfSetupVerb.gesture].
  final PerfStep? gesture;

  /// The route for `navigate`, the text for `wait_for_text`.
  final String? argument;

  /// `wait_for_text`'s ceiling in milliseconds.
  final int? timeoutMs;

  Object toJson() => switch (verb) {
        PerfSetupVerb.hotRestart ||
        PerfSetupVerb.waitForNetworkIdle =>
          verb.wire,
        PerfSetupVerb.waitForText => <String, Object?>{
            verb.wire: <String, Object?>{
              'text': argument,
              'timeout_ms': timeoutMs,
            },
          },
        PerfSetupVerb.navigate => <String, Object?>{verb.wire: argument},
        PerfSetupVerb.gesture => gesture!.toJson(),
      };
}

/// One step of the measured window.
final class PerfStep {
  const PerfStep(
    this.verb, {
    this.target,
    this.text,
    this.key,
    this.route,
    this.dx = 0,
    this.dy = 0,
    this.ticks = 1,
    this.width,
    this.height,
    this.ms,
    this.only,
  });

  final PerfStepVerb verb;
  final PerfTarget? target;

  /// The text `fill` and `type` enter.
  final String? text;

  /// The key `press_key` sends.
  final String? key;

  /// The route `navigate` opens.
  final String? route;

  /// Logical pixels for `scroll`, `wheel` and `drag`.
  final double dx;
  final double dy;

  /// How many wheel events `wheel` sends, each of [dx]/[dy], at the one
  /// point it resolved. A real wheel is many small ticks; one large event
  /// jumps the scroll in a single frame and measures almost nothing.
  final int ticks;

  /// The viewport `resize` sets, in CSS pixels.
  final int? width;
  final int? height;

  /// How long `wait` pauses, in milliseconds.
  final int? ms;

  /// The platforms the step is limited to; null runs it everywhere the
  /// scenario runs.
  final Set<PerfPlatform>? only;

  bool runsOn(PerfPlatform platform) => only?.contains(platform) ?? true;

  Map<String, Object?> toJson() {
    final Object args = switch (verb) {
      PerfStepVerb.navigate => route!,
      PerfStepVerb.wait => ms!,
      PerfStepVerb.pressKey => <String, Object?>{'key': key},
      PerfStepVerb.resize => <String, Object?>{
          'width': width,
          'height': height,
        },
      _ => <String, Object?>{
          'target': target!.toJson(),
          if (text != null) 'text': text,
          if (dx != 0) 'dx': dx,
          if (dy != 0) 'dy': dy,
          if (ticks != 1) 'ticks': ticks,
        },
    };
    return <String, Object?>{
      verb.wire: args,
      if (only != null) 'only': only!.map((PerfPlatform p) => p.name).toList(),
    };
  }
}

/// How large a per-metric change has to be before `dusk:perf_compare` calls
/// it a warning or an error, in percent.
final class PerfThresholds {
  const PerfThresholds({this.warnPct = 10, this.errorPct = 25});

  /// Reads a `thresholds` block, keeping the default for any key it lacks.
  factory PerfThresholds.fromJson(Object? json) {
    const PerfThresholds defaults = PerfThresholds();
    if (json is! Map<Object?, Object?>) return defaults;
    final Object? warn = json['warn'];
    final Object? error = json['error'];
    return PerfThresholds(
      warnPct: warn is num ? warn.toDouble() : defaults.warnPct,
      errorPct: error is num ? error.toDouble() : defaults.errorPct,
    );
  }

  final double warnPct;
  final double errorPct;

  Map<String, Object?> toJson() => <String, Object?>{
        'warn': _plainNumber(warnPct),
        'error': _plainNumber(errorPct),
      };
}

/// A validated scenario.
final class PerfScenario {
  const PerfScenario({
    required this.name,
    required this.platforms,
    required this.setup,
    required this.steps,
    this.viewport,
    this.repeat = 3,
    this.thresholds = const PerfThresholds(),
  });

  /// Parses and validates [source].
  ///
  /// Throws [PerfScenarioException] listing every problem found; a YAML
  /// syntax error is reported as one problem.
  static PerfScenario parse(String source) {
    final Object? document;
    try {
      document = loadYaml(source);
    } on YamlException catch (e) {
      throw PerfScenarioException(<String>['not valid YAML: ${e.message}']);
    }
    if (document is! Map<Object?, Object?>) {
      throw PerfScenarioException(<String>[
        'the document must be a map with name, steps and the optional keys',
      ]);
    }
    return _ScenarioReader(document).read();
  }

  /// Also the file name stem, so restricted to [isSafePerfName].
  final String name;

  /// Applied through CDP on Chrome; the device's own on android and ios.
  final ({int width, int height})? viewport;
  final Set<PerfPlatform> platforms;

  /// Runs before EVERY repeat, so each one starts from the same state.
  final List<PerfSetupStep> setup;
  final List<PerfStep> steps;
  final int repeat;
  final PerfThresholds thresholds;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        if (viewport != null)
          'viewport': <String, Object?>{
            'width': viewport!.width,
            'height': viewport!.height,
          },
        'platforms': PerfPlatform.values
            .where(platforms.contains)
            .map((PerfPlatform p) => p.name)
            .toList(),
        'setup': setup.map((PerfSetupStep s) => s.toJson()).toList(),
        'steps': steps.map((PerfStep s) => s.toJson()).toList(),
        'repeat': repeat,
        'thresholds': thresholds.toJson(),
      };
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Reads one YAML document into a [PerfScenario], collecting every problem.
final class _ScenarioReader {
  _ScenarioReader(this.document);

  final Map<Object?, Object?> document;
  final List<String> problems = <String>[];

  PerfScenario read() {
    // 1. The scalar keys.
    final Object? rawName = document['name'];
    final String name = rawName is String ? rawName : '';
    if (!isSafePerfName(name)) {
      problems.add(
        'name "${rawName ?? ''}" must be non-empty and use [a-z0-9_-] only: '
        'it becomes part of the output file name.',
      );
    }
    final int repeat = _positiveInt(document['repeat'], 'repeat') ?? 3;
    final ({int width, int height})? viewport = _viewport(document['viewport']);
    final Set<PerfPlatform> platforms = _platforms(
          document['platforms'],
          'platforms',
        ) ??
        PerfPlatform.values.toSet();
    final PerfThresholds thresholds = _thresholds(document['thresholds']);

    // 2. The lists. Steps are checked against the platforms read above.
    final List<PerfSetupStep> setup = _setup(document['setup'], platforms);
    final List<PerfStep> steps = _steps(document['steps'], platforms);

    for (final Object? key in document.keys) {
      if (!_kTopLevelKeys.contains(key)) {
        problems
            .add('unknown key "$key"; allowed: ${_kTopLevelKeys.join(', ')}.');
      }
    }

    if (problems.isNotEmpty) throw PerfScenarioException(problems);
    return PerfScenario(
      name: name,
      viewport: viewport,
      platforms: platforms,
      setup: setup,
      steps: steps,
      repeat: repeat,
      thresholds: thresholds,
    );
  }

  ({int width, int height})? _viewport(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map<Object?, Object?>) {
      problems.add('viewport must be {width, height}.');
      return null;
    }
    final int? width = _positiveInt(raw['width'], 'viewport.width');
    final int? height = _positiveInt(raw['height'], 'viewport.height');
    if (width == null || height == null) {
      if (raw['width'] == null || raw['height'] == null) {
        problems.add('viewport needs both width and height.');
      }
      return null;
    }
    return (width: width, height: height);
  }

  Set<PerfPlatform>? _platforms(Object? raw, String where) {
    if (raw == null) return null;
    if (raw is! List<Object?> || raw.isEmpty) {
      problems.add('$where must be a non-empty list of chrome, android, ios.');
      return null;
    }
    final Set<PerfPlatform> platforms = <PerfPlatform>{};
    for (final Object? entry in raw) {
      final PerfPlatform? platform = PerfPlatform.tryParse(entry);
      if (platform == null) {
        problems.add('$where: "$entry" is not one of chrome, android, ios.');
        continue;
      }
      platforms.add(platform);
    }
    return platforms;
  }

  PerfThresholds _thresholds(Object? raw) {
    if (raw == null) return const PerfThresholds();
    if (raw is! Map<Object?, Object?>) {
      problems.add('thresholds must be {warn, error}, in percent.');
      return const PerfThresholds();
    }
    final PerfThresholds thresholds = PerfThresholds.fromJson(raw);
    if (thresholds.warnPct <= 0 || thresholds.warnPct >= thresholds.errorPct) {
      problems.add(
        'thresholds: warn (${thresholds.warnPct}) must be above 0 and below '
        'error (${thresholds.errorPct}).',
      );
    }
    return thresholds;
  }

  List<PerfSetupStep> _setup(Object? raw, Set<PerfPlatform> platforms) {
    if (raw == null) return const <PerfSetupStep>[];
    if (raw is! List<Object?>) {
      problems.add('setup must be a list.');
      return const <PerfSetupStep>[];
    }
    final List<PerfSetupStep> setup = <PerfSetupStep>[];
    for (int i = 0; i < raw.length; i++) {
      final PerfSetupStep? step = _setupStep(raw[i], 'setup[$i]', platforms);
      if (step != null) setup.add(step);
    }
    return setup;
  }

  PerfSetupStep? _setupStep(
    Object? raw,
    String where,
    Set<PerfPlatform> platforms,
  ) {
    final (String? wire, Object? args) =
        _verbEntry(raw, where, const <String>{'only'});
    if (wire == null) return null;

    // 1. A gesture is read exactly as a step is, `only` and all.
    final PerfStepVerb? gesture = PerfStepVerb.tryParse(wire);
    if (gesture != null && kPerfSetupGestures.contains(gesture)) {
      final PerfStep? step = _step(raw, where, platforms);
      return step == null ? null : PerfSetupStep.gesture(step);
    }

    // 2. Anything else is a setup verb, which runs everywhere.
    final PerfSetupVerb? verb = PerfSetupVerb.tryParse(wire);
    if (verb == null) {
      final Iterable<String> allowed = <String>[
        for (final PerfSetupVerb v in PerfSetupVerb.values)
          if (v != PerfSetupVerb.gesture) v.wire,
        for (final PerfStepVerb v in kPerfSetupGestures) v.wire,
      ];
      problems.add(
        '$where: unknown setup verb "$wire"; allowed: ${allowed.join(', ')}.',
      );
      return null;
    }
    if (raw is Map<Object?, Object?> && raw.containsKey('only')) {
      problems.add('$where: only limits a gesture; ${verb.wire} runs on every '
          'platform the scenario lists.');
    }
    switch (verb) {
      case PerfSetupVerb.gesture:
        throw StateError('PerfSetupVerb.tryParse never answers gesture.');
      case PerfSetupVerb.hotRestart:
      case PerfSetupVerb.waitForNetworkIdle:
        return PerfSetupStep(verb);
      case PerfSetupVerb.navigate:
        final String? route = _string(args, '$where.navigate');
        return route == null ? null : PerfSetupStep(verb, argument: route);
      case PerfSetupVerb.waitForText:
        if (args is Map<Object?, Object?>) {
          final String? text = _string(args['text'], '$where.text');
          final int? timeout = args['timeout_ms'] == null
              ? kPerfWaitForTextTimeoutMs
              : _positiveInt(args['timeout_ms'], '$where.timeout_ms');
          if (text == null || timeout == null) return null;
          return PerfSetupStep(verb, argument: text, timeoutMs: timeout);
        }
        final String? text = _string(args, '$where.wait_for_text');
        return text == null
            ? null
            : PerfSetupStep(
                verb,
                argument: text,
                timeoutMs: kPerfWaitForTextTimeoutMs,
              );
    }
  }

  List<PerfStep> _steps(Object? raw, Set<PerfPlatform> platforms) {
    if (raw is! List<Object?> || raw.isEmpty) {
      problems.add('steps must be a non-empty list: a session that drives '
          'nothing draws no frames and perf_end refuses it.');
      return const <PerfStep>[];
    }
    final List<PerfStep> steps = <PerfStep>[];
    for (int i = 0; i < raw.length; i++) {
      final PerfStep? step = _step(raw[i], 'steps[$i]', platforms);
      if (step != null) steps.add(step);
    }
    return steps;
  }

  PerfStep? _step(Object? raw, String where, Set<PerfPlatform> platforms) {
    final (String? wire, Object? args) =
        _verbEntry(raw, where, const <String>{'only'});
    if (wire == null) return null;
    final PerfStepVerb? verb = PerfStepVerb.tryParse(wire);
    if (verb == null) {
      problems.add(
        '$where: unknown step verb "$wire"; allowed: '
        '${PerfStepVerb.values.map((PerfStepVerb v) => v.wire).join(', ')}.',
      );
      return null;
    }
    final String at = '$where.${verb.wire}';

    // 1. Where it runs, and whether its verb can run there.
    final Set<PerfPlatform>? only = raw is Map<Object?, Object?>
        ? _platforms(raw['only'], '$where.only')
        : null;
    if (only != null && !only.every(platforms.contains)) {
      problems.add('$where.only names a platform the scenario does not list.');
    }
    final Set<PerfPlatform> effective = only ?? platforms;
    if (verb.chromeOnly &&
        effective.any((PerfPlatform p) => p != PerfPlatform.chrome)) {
      final String others = effective
          .where((PerfPlatform p) => p != PerfPlatform.chrome)
          .map((PerfPlatform p) => p.name)
          .join(', ');
      problems.add(
        '$where: ${verb.wire} drives Chrome DevTools and would run on $others. '
        'Add `only: [chrome]`${verb == PerfStepVerb.wheel ? ', and a drag with `only: [android, ios]` to scroll there' : ''}.',
      );
    }

    // 2. The verb's own arguments.
    switch (verb) {
      case PerfStepVerb.navigate:
        final String? route = _string(args, at);
        return route == null ? null : PerfStep(verb, route: route, only: only);
      case PerfStepVerb.wait:
        final int? ms = _positiveInt(args, at);
        return ms == null ? null : PerfStep(verb, ms: ms, only: only);
      case PerfStepVerb.pressKey:
        final Object? key = args is Map<Object?, Object?> ? args['key'] : args;
        final String? name = _string(key, '$at.key');
        return name == null ? null : PerfStep(verb, key: name, only: only);
      case PerfStepVerb.resize:
        if (args is! Map<Object?, Object?>) {
          problems.add('$at must be {width, height}.');
          return null;
        }
        final int? width = _positiveInt(args['width'], '$at.width');
        final int? height = _positiveInt(args['height'], '$at.height');
        if (width == null || height == null) return null;
        return PerfStep(verb, width: width, height: height, only: only);
      case PerfStepVerb.tap:
      case PerfStepVerb.fill:
      case PerfStepVerb.type:
      case PerfStepVerb.scroll:
      case PerfStepVerb.wheel:
      case PerfStepVerb.drag:
        return _targetStep(verb, args, at, only);
    }
  }

  PerfStep? _targetStep(
    PerfStepVerb verb,
    Object? args,
    String at,
    Set<PerfPlatform>? only,
  ) {
    if (args is! Map<Object?, Object?>) {
      problems.add('$at must be a map with a target.');
      return null;
    }
    for (final String stale in const <String>['ref', 'startRef', 'endRef']) {
      if (args.containsKey(stale)) {
        problems.add(
          '$at: "$stale" is a ref, and a ref is stale after the next '
          'navigate. Name the widget with a target resolved at run time: '
          'exactly one of {text}, {label}, {role, name}, {key}.',
        );
      }
    }
    final PerfTarget? target = _target(args['target'], '$at.target');

    final bool typing = verb == PerfStepVerb.fill || verb == PerfStepVerb.type;
    final String? text = typing ? _string(args['text'], '$at.text') : null;
    final double dx = _number(args['dx'], '$at.dx');
    final double dy = _number(args['dy'], '$at.dy');
    final bool moves = verb == PerfStepVerb.scroll ||
        verb == PerfStepVerb.wheel ||
        verb == PerfStepVerb.drag;
    if (moves && dx == 0 && dy == 0) {
      problems.add('$at needs a non-zero dx or dy.');
    }
    int ticks = 1;
    if (args.containsKey('ticks')) {
      if (verb != PerfStepVerb.wheel) {
        problems.add('$at: ticks applies to wheel only.');
      } else {
        final Object? raw = args['ticks'];
        if (raw is int && raw >= 1 && raw <= _kMaxWheelTicks) {
          ticks = raw;
        } else {
          problems.add(
            '$at.ticks must be a whole number from 1 to $_kMaxWheelTicks.',
          );
        }
      }
    }
    if (target == null || (typing && text == null)) return null;
    return PerfStep(
      verb,
      target: target,
      text: text,
      dx: dx,
      dy: dy,
      ticks: ticks,
      only: only,
    );
  }

  PerfTarget? _target(Object? raw, String at) {
    if (raw is! Map<Object?, Object?>) {
      problems.add(
        '$at "${raw ?? ''}" must be a map resolved at run time: exactly one '
        'of {text}, {label}, {role, name}, {key}, plus an optional index. A '
        'literal ref such as e12 is stale after the next navigate.',
      );
      return null;
    }
    final List<PerfTargetKind> kinds = PerfTargetKind.values
        .where((PerfTargetKind k) => raw.containsKey(k.name))
        .toList();
    if (kinds.length != 1) {
      problems.add(
        '$at must name exactly one of text, label, role, key '
        '(found ${kinds.isEmpty ? 'none' : kinds.map((PerfTargetKind k) => k.name).join(', ')}).',
      );
      return null;
    }
    final PerfTargetKind kind = kinds.single;
    final int index = raw['index'] == null
        ? 0
        : (_nonNegativeInt(raw['index'], '$at.index') ?? 0);
    if (kind == PerfTargetKind.key && index != 0) {
      problems.add('$at.index: a key names one widget, so an index is not '
          'supported on a key target.');
    }
    // `ext.dusk.find` takes no index, and the list extension behind a label
    // index walks only the root pipeline owner, which holds no semantics
    // tree in a running app: an index here would match nothing, every time.
    if (kind == PerfTargetKind.label && index != 0) {
      problems.add('$at.index: a label target cannot be indexed; name the '
          'control as {role, name, index} with the role dusk:snap prints, or '
          'use {text, index}.');
    }
    if (kind != PerfTargetKind.role) {
      final String? value = _string(raw[kind.name], '$at.${kind.name}');
      return value == null
          ? null
          : PerfTarget(kind: kind, value: value, index: index);
    }
    final Object? role = raw['role'];
    if (!kPerfTargetRoles.contains(role)) {
      problems.add(
        '$at.role "$role" is not one of ${kPerfTargetRoles.join(', ')}, the '
        'roles dusk:snap prints.',
      );
    }
    final String? name = _string(raw['name'], '$at.name');
    if (name == null || !kPerfTargetRoles.contains(role)) return null;
    return PerfTarget(
      kind: kind,
      value: name,
      role: role! as String,
      index: index,
    );
  }

  /// Splits `verb` or `{verb: args, <allowed>...}` into the verb and its
  /// arguments; reports and returns `(null, null)` otherwise.
  (String?, Object?) _verbEntry(
      Object? raw, String where, Set<String> allowed) {
    if (raw is String) return (raw, null);
    if (raw is Map<Object?, Object?>) {
      final List<Object?> verbs =
          raw.keys.where((Object? k) => !allowed.contains(k)).toList();
      if (verbs.length == 1 && verbs.single is String) {
        return (verbs.single! as String, raw[verbs.single]);
      }
    }
    problems.add('$where must be one verb, as `verb` or `verb: arguments`.');
    return (null, null);
  }

  String? _string(Object? raw, String at) {
    if (raw is String && raw.isNotEmpty) return raw;
    problems.add('$at must be a non-empty string.');
    return null;
  }

  int? _positiveInt(Object? raw, String at) {
    if (raw == null) return null;
    if (raw is int && raw > 0) return raw;
    problems.add('$at must be a positive integer (got $raw).');
    return null;
  }

  int? _nonNegativeInt(Object? raw, String at) {
    if (raw is int && raw >= 0) return raw;
    problems.add('$at must be a non-negative integer (got $raw).');
    return null;
  }

  double _number(Object? raw, String at) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    problems.add('$at must be a number (got $raw).');
    return 0;
  }
}

const Set<String> _kTopLevelKeys = <String>{
  'name',
  'viewport',
  'platforms',
  'setup',
  'steps',
  'repeat',
  'thresholds',
};

/// `10` rather than `10.0` in the written file when the value is whole.
num _plainNumber(double value) =>
    value == value.roundToDouble() ? value.toInt() : value;
