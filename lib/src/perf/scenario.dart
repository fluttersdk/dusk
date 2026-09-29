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
///
/// A file on disk loads through [loadPerfScenarios] (`scenario_loader.dart`),
/// which adds setup fragments (`include`), `${...}` interpolation, secrets
/// and `variants`; [PerfScenario.parse] reads the same grammar from a string,
/// without the includes a string has no directory to resolve.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'perf_support.dart';

part 'scenario_loader.dart';

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

  /// Whether the step can create, remove or move a widget a later step
  /// targets: everything that dispatches into the app or changes its layout.
  /// Only `wait` cannot, so a target behind nothing but waits already exists
  /// where it will be when its step runs.
  bool get movesTargets => this != wait;

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

/// How long a `when` guard polls when it names no `timeout_ms`: a cold start
/// on a device can take most of a minute to show its first screen.
const int kPerfWhenTimeoutMs = 60000;

/// How deep includes may nest, the scenario file itself not counted.
const int kPerfMaxIncludeDepth = 8;

/// The fewest characters a secret may have. Every output is masked for every
/// secret wherever its text appears, so a shorter one (`1`, `80`) would mask
/// every such number in every log line, run file and envelope.
const int kPerfMinSecretLength = 4;

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

/// The widget a step acts on, resolved against the live tree in every
/// repeat: before `perf_begin` when no earlier step can move it
/// ([PerfStepVerb.movesTargets]), else right before its step. Never a ref:
/// an `e<N>` or `q<N>` minted by one run is stale after the next navigate.
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

/// The `when:` of an include: whether the steps it flattened run at all.
///
/// A runner polls the screen for up to [timeoutMs]. [text] on screen runs
/// the group; [unlessText] on screen skips it, and wins when both are there,
/// since it names the state the group would produce (a login that already
/// happened). On timeout the group is skipped when [unlessText] is null, and
/// the run fails when it is set: the screen showed neither state.
///
/// Every step flattened out of one guarded include carries the same instance
/// (compare with `identical`, never `==`), and the guard of an include nested
/// inside it names it as [parent]. A runner decides each guard once per pass
/// over the setup, outermost first, at the first step that carries it, and
/// skips every step whose chain holds a guard it decided to skip.
final class PerfSetupGuard {
  PerfSetupGuard({
    required this.text,
    required this.origin,
    this.unlessText,
    this.timeoutMs = kPerfWhenTimeoutMs,
    this.parent,
  });

  /// The text whose showing runs the guarded steps.
  final String text;

  /// The text whose showing skips them; it wins when both show.
  final String? unlessText;

  /// How long the guard polls for either text, in milliseconds.
  final int timeoutMs;

  /// The include entry the guard belongs to, as [PerfSetupStep.origin]
  /// spells a location: `setup[1]`, `fragments/login.yaml steps[0]`.
  final String origin;

  /// The guard of the include this one is nested in, if that one has one.
  final PerfSetupGuard? parent;

  /// The `when:` as the run file echoes it, [parentJson] as its `parent`
  /// when the enclosing guard is echoed on the same step. Never holds a
  /// secret: the loader refuses one anywhere in a `when`.
  Map<String, Object?> toJson({Map<String, Object?>? parentJson}) =>
      <String, Object?>{
        'text': text,
        if (unlessText != null) 'unless_text': unlessText,
        'timeout_ms': timeoutMs,
        if (parentJson != null) 'parent': parentJson,
      };
}

/// One setup entry.
final class PerfSetupStep {
  const PerfSetupStep(
    this.verb, {
    this.argument,
    this.timeoutMs,
    this.origin,
    this.guard,
  }) : gesture = null;

  /// A gesture from the steps' grammar, run unmeasured before the window.
  const PerfSetupStep.gesture(
    PerfStep this.gesture, {
    this.origin,
    this.guard,
  })  : verb = PerfSetupVerb.gesture,
        argument = null,
        timeoutMs = null;

  final PerfSetupVerb verb;

  /// The gesture, set only for [PerfSetupVerb.gesture].
  final PerfStep? gesture;

  /// The route for `navigate`, the text for `wait_for_text`.
  final String? argument;

  /// `wait_for_text`'s ceiling in milliseconds.
  final int? timeoutMs;

  /// Where the entry was written, for a runner's error messages: `setup[2]`
  /// in the scenario, `fragments/login.yaml steps[1]` when an include
  /// flattened it here. Null only on a step built by hand.
  final String? origin;

  /// The innermost `when` guard of the includes that flattened the entry;
  /// null when it runs unconditionally.
  final PerfSetupGuard? guard;

  /// This entry at its place in the flattened list.
  PerfSetupStep _placed(String origin, PerfSetupGuard? guard) =>
      verb == PerfSetupVerb.gesture
          ? PerfSetupStep.gesture(gesture!, origin: origin, guard: guard)
          : PerfSetupStep(
              verb,
              argument: argument,
              timeoutMs: timeoutMs,
              origin: origin,
              guard: guard,
            );

  /// The entry as the run file writes it: the verb alone, or a map of the
  /// verb and its arguments.
  ///
  /// [opens] are the guards this entry is the first of its list to carry,
  /// outermost first ([PerfScenario.toJson] works them out): the innermost
  /// is echoed as `when`, each enclosing one as the `parent` of the one it
  /// encloses. A verb written alone becomes `{verb: null, when: ...}` then,
  /// so a reader sees which steps a guard may have skipped.
  Object toJson({List<PerfSetupGuard> opens = const <PerfSetupGuard>[]}) {
    final Object entry = switch (verb) {
      PerfSetupVerb.hotRestart || PerfSetupVerb.waitForNetworkIdle => verb.wire,
      PerfSetupVerb.waitForText => <String, Object?>{
          verb.wire: <String, Object?>{
            'text': argument,
            'timeout_ms': timeoutMs,
          },
        },
      PerfSetupVerb.navigate => <String, Object?>{verb.wire: argument},
      PerfSetupVerb.gesture => gesture!.toJson(),
    };
    if (opens.isEmpty) return entry;
    Map<String, Object?>? when;
    for (final PerfSetupGuard guard in opens) {
      when = guard.toJson(parentJson: when);
    }
    return <String, Object?>{
      if (entry is Map<String, Object?>) ...entry else entry as String: null,
      'when': when,
    };
  }
}

/// [setup] as the run file writes it: each guard echoed once, on the first
/// entry it governs, so a guarded group reads as guarded.
List<Object> _setupJson(List<PerfSetupStep> setup) {
  final Set<PerfSetupGuard> echoed = Set<PerfSetupGuard>.identity();
  final List<Object> entries = <Object>[];
  for (final PerfSetupStep step in setup) {
    // The entry's chain, outermost first; the guards not echoed yet are a
    // suffix of it, since an enclosing guard governs every entry its inner
    // ones do.
    final List<PerfSetupGuard> chain = <PerfSetupGuard>[
      for (PerfSetupGuard? g = step.guard; g != null; g = g.parent) g,
    ].reversed.toList();
    final List<PerfSetupGuard> opens = <PerfSetupGuard>[
      for (final PerfSetupGuard guard in chain)
        if (!echoed.contains(guard)) guard,
    ];
    echoed.addAll(opens);
    entries.add(step.toJson(opens: opens));
  }
  return entries;
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
    this.secret = false,
  });

  final PerfStepVerb verb;
  final PerfTarget? target;

  /// The text `fill` and `type` enter.
  final String? text;

  /// Whether [text] came from `${env.*}` or a `secret: true` param, so
  /// [toJson] writes `***` in its place.
  final bool secret;

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
          if (text != null) 'text': secret ? '***' : text,
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
    this.variant,
  });

  /// Parses and validates [source], interpolating `$$` and `${env.*}`
  /// against an empty environment.
  ///
  /// Throws [PerfScenarioException] listing every problem found; a YAML
  /// syntax error is reported as one problem. An `include` or `variants` is
  /// one of them: an include resolves against the including file's directory
  /// and variants yield several scenarios, so both need [loadPerfScenarios].
  static PerfScenario parse(String source) =>
      _ScenarioReader().readScenarios(_scenarioDocument(source)).single;

  /// Also the file name stem, so restricted to [isSafePerfName].
  final String name;

  /// The `variants:` key this scenario was read from, as text (the name
  /// ends in `-<variant>`); null for a file without variants. Not echoed by
  /// [toJson]: the name already carries it.
  final String? variant;

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
        'setup': _setupJson(setup),
        'steps': steps.map((PerfStep s) => s.toJson()).toList(),
        'repeat': repeat,
        'thresholds': thresholds.toJson(),
      };
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Reads a scenario document, or a bare setup list, into the model,
/// collecting every problem.
///
/// Reading is one pass per source file: [_plain] copies the YAML into plain
/// values and interpolates every scalar once, a value from `${env.*}` or a
/// secret param becoming a [_Secret]; the readers then take a [_Secret] only
/// as the text of a `fill` or `type` ([_screenEntry]) and pass it through an
/// include's `with:`. Includes are the loader's (`scenario_loader.dart`).
final class _ScenarioReader {
  _ScenarioReader({this.env = const <String, String>{}, this.file});

  final Map<String, String> env;

  /// The absolute path of the file being read; null for a string, which
  /// can hold neither an include nor variants.
  final String? file;

  final List<String> problems = <String>[];

  /// Every tainted value read so far; [_fail] masks them in [problems].
  final Set<String> secrets = <String>{};

  /// Problems that quote no value, so [_fail] leaves them unmasked: a short
  /// secret's own report would otherwise lose its length and the variable's
  /// name to the mask it explains.
  final List<String> _unmasked = <String>[];

  /// The name of every environment variable a `${env.NAME}` read, so a
  /// caller can keep them out of the processes it starts.
  final Set<String> envNames = <String>{};

  /// The scenarios [source] holds: one per variant, or itself.
  List<PerfScenario> readScenarios(Map<Object?, Object?> source) {
    // 1. One interpolation pass over the whole file, so every scalar is read
    //    exactly once whichever variant ends up using it.
    final Map<Object?, Object?> document =
        _plain(source, const <String, Object>{}, _rootLabel, '')!
            as Map<Object?, Object?>;

    // 2. Keys no scenario takes.
    final Set<String> allowed = <String>{
      ..._kTopLevelKeys,
      if (file != null) 'variants',
    };
    for (final Object? key in document.keys) {
      if (key == 'variants' && file == null) {
        problems.add('variants: a file with variants holds several scenarios; '
            'load it with loadPerfScenarios.');
      } else if (!allowed.contains(key)) {
        problems.add('unknown key "$key"; allowed: ${allowed.join(', ')}.');
      }
    }

    // 3. Each variant is a scenario of its own, validated on its own.
    final Object? variants = document['variants'];
    final List<PerfScenario> scenarios = variants == null || file == null
        ? <PerfScenario>[_readOne(document)]
        : _readVariants(document, variants);
    _fail();
    return scenarios;
  }

  /// The flattened setup a bare entry list (a campaign's `after_start:`)
  /// holds, read at [at].
  List<PerfSetupStep> readSetup(
    Object? entries,
    String at,
    Set<PerfPlatform> platforms,
  ) {
    final List<PerfSetupStep> setup = <PerfSetupStep>[];
    final Object? plain = _plain(
      entries,
      const <String, Object>{},
      _rootLabel,
      at,
    );
    if (plain != null) _setupList(plain, at, platforms, _rootFrame, setup);
    _fail();
    return setup;
  }

  PerfScenario _readOne(
    Map<Object?, Object?> document, {
    String? variant,
    String stepsAt = 'steps',
  }) {
    // 1. The scalar keys. None takes a secret.
    final Object? rawName = _screen(document['name'], 'name');
    final String name = rawName is String ? rawName : '';
    if (!isSafePerfName(name)) {
      problems.add(
        'name "${rawName ?? ''}" must be non-empty and use [a-z0-9_-] only: '
        'it becomes part of the output file name.',
      );
    }
    final int repeat =
        _positiveInt(_screen(document['repeat'], 'repeat'), 'repeat') ?? 3;
    final ({int width, int height})? viewport =
        _viewport(_screen(document['viewport'], 'viewport'));
    final Set<PerfPlatform> platforms = _platforms(
          _screen(document['platforms'], 'platforms'),
          'platforms',
        ) ??
        PerfPlatform.values.toSet();
    final PerfThresholds thresholds =
        _thresholds(_screen(document['thresholds'], 'thresholds'));

    // 2. The lists. Steps are checked against the platforms read above.
    final List<PerfSetupStep> setup = <PerfSetupStep>[];
    if (document['setup'] != null) {
      _setupList(document['setup'], 'setup', platforms, _rootFrame, setup);
    }
    final List<PerfStep> steps = _steps(document['steps'], stepsAt, platforms);

    return PerfScenario(
      name: variant == null ? name : '$name-$variant',
      viewport: viewport,
      platforms: platforms,
      setup: setup,
      steps: steps,
      repeat: repeat,
      thresholds: thresholds,
      variant: variant,
    );
  }

  List<PerfScenario> _readVariants(
    Map<Object?, Object?> document,
    Object? raw,
  ) {
    if (raw is! Map<Object?, Object?> || raw.isEmpty) {
      problems.add('variants must be a non-empty map of <key>: {viewport, '
          'platforms, repeat, steps}; leave it out for one scenario.');
      return const <PerfScenario>[];
    }
    final List<PerfScenario> scenarios = <PerfScenario>[];
    final Set<String> seen = <String>{};
    for (final MapEntry<Object?, Object?>(:Object? key, :Object? value)
        in raw.entries) {
      // 1. YAML reads `1440:` as an int, so the key is checked as the text
      //    it becomes in the name.
      final String suffix = '$key';
      if (!isSafePerfName(suffix)) {
        problems.add('variants: key "$suffix" must use [a-z0-9_-] only: it '
            'ends the scenario name and the file name.');
        continue;
      }
      if (!seen.add(suffix)) {
        problems.add('variants: key "$suffix" appears twice; 390 and "390" '
            'name one variant.');
        continue;
      }
      final Object overrides = value ?? const <Object?, Object?>{};
      if (overrides is! Map<Object?, Object?>) {
        problems.add('variants.$suffix must be a map of '
            '${_kVariantKeys.join(', ')}.');
        continue;
      }
      final Iterable<Object?> unknown =
          overrides.keys.where((Object? k) => !_kVariantKeys.contains(k));
      for (final Object? k in unknown) {
        problems.add('variants.$suffix: unknown key "$k"; allowed: '
            '${_kVariantKeys.join(', ')}.');
      }
      if (unknown.isNotEmpty) continue;

      // 2. Each key the variant names replaces the base's whole value, so a
      //    variant's steps are its steps, checked against its platforms.
      final int from = problems.length;
      final PerfScenario scenario = _readOne(
        <Object?, Object?>{...document, ...overrides}..remove('variants'),
        variant: suffix,
        stepsAt:
            overrides.containsKey('steps') ? 'variants.$suffix.steps' : 'steps',
      );
      for (int i = from; i < problems.length; i++) {
        problems[i] = '${scenario.name}: ${problems[i]}';
      }
      scenarios.add(scenario);
    }
    return scenarios;
  }

  _Frame get _rootFrame => _Frame(
        file: file,
        chain: <String>[if (file != null) file!],
      );

  /// How interpolation problems name the file being read.
  String get _rootLabel => file == null ? '' : _shown(file!);

  /// Throws the problems collected so far, secrets masked.
  void _fail() {
    if (problems.isEmpty && _unmasked.isEmpty) return;
    final List<String> masks = <String>[
      for (final String secret in secrets) ...<String>{
        secret,
        perfJsonInner(secret),
      },
    ]..sort((String a, String b) => b.length.compareTo(a.length));
    throw PerfScenarioException(<String>[
      for (final String problem in problems)
        masks.fold(
          problem,
          (String line, String mask) => line.replaceAll(mask, '***'),
        ),
      ..._unmasked,
    ]);
  }

  // -------------------------------------------------------------------------
  // Interpolation and secrets
  // -------------------------------------------------------------------------

  /// A plain copy of [node] with every string scalar interpolated once in
  /// [scope] (param name to a String or a [_Secret]); keys are copied as
  /// written. [label] and [at] name the file and the path in a problem.
  Object? _plain(
    Object? node,
    Map<String, Object> scope,
    String label,
    String at,
  ) =>
      switch (node) {
        Map<Object?, Object?>() => <Object?, Object?>{
            for (final MapEntry<Object?, Object?>(:Object? key, :Object? value)
                in node.entries)
              key: _plain(
                value,
                scope,
                label,
                at.isEmpty ? '$key' : '$at.$key',
              ),
          },
        List<Object?>() => <Object?>[
            for (final (int i, Object? value) in node.indexed)
              _plain(value, scope, label, '$at[$i]'),
          ],
        String() => _interpolate(node, scope, label, at),
        _ => node,
      };

  /// [source] with `${name}` read from [scope], `${env.NAME}` from [env] and
  /// `$$` as one `$`. A substituted value is never scanned again, so a `$`
  /// inside it stays as it is. Answers a [_Secret] when any part was one.
  Object _interpolate(
    String source,
    Map<String, Object> scope,
    String label,
    String at,
  ) {
    if (!source.contains(r'$')) return source;
    final String where = label.isEmpty ? at : '$label $at';
    final StringBuffer out = StringBuffer();
    bool tainted = false;
    int i = 0;
    while (i < source.length) {
      final String next = i + 1 < source.length ? source[i + 1] : '';
      if (source[i] != r'$' || (next != r'$' && next != '{')) {
        out.write(source[i]);
        i++;
        continue;
      }
      if (next == r'$') {
        out.write(r'$');
        i += 2;
        continue;
      }
      final int close = source.indexOf('}', i + 2);
      if (close < 0) {
        problems.add(
          '$where: "\${" is never closed; write \$\$ for a literal \$.',
        );
        return source;
      }
      final String name = source.substring(i + 2, close);
      final Object? value = _lookup(name, scope, where);
      if (value is _Secret) tainted = true;
      out.write(value is _Secret ? value.value : value ?? '');
      i = close + 1;
    }
    return tainted ? _Secret(out.toString()) : out.toString();
  }

  /// What `${name}` stands for; null after reporting it undefined.
  Object? _lookup(String name, Map<String, Object> scope, String where) {
    if (name.startsWith('env.')) {
      final String variable = name.substring(4);
      final String? value = env[variable];
      if (value == null) {
        problems.add('$where: \${$name} is not set in the environment.');
        return null;
      }
      // Reported once per variable, at the first place that reads it.
      if (envNames.add(variable) && value.isNotEmpty) {
        _refuseShortSecret(value, where, '\${$name}');
      }
      if (value.isNotEmpty) secrets.add(value);
      return _Secret(value);
    }
    final Object? value = scope[name];
    if (value == null) {
      final String known = scope.isEmpty
          ? 'this file declares no params'
          : 'params: ${scope.keys.join(', ')}';
      problems.add(
        '$where: \${$name} is not defined here; $known, '
        r'and ${env.NAME} reads the environment.',
      );
    }
    return value;
  }

  /// [node] with every [_Secret] in it refused, reported at its path and
  /// replaced by `***`, so no later problem can quote it.
  Object? _screen(Object? node, String at) => switch (node) {
        _Secret() => _refuseSecret(at),
        Map<Object?, Object?>() => <Object?, Object?>{
            for (final MapEntry<Object?, Object?>(:Object? key, :Object? value)
                in node.entries)
              key: _screen(value, '$at.$key'),
          },
        List<Object?>() => <Object?>[
            for (final (int i, Object? value) in node.indexed)
              _screen(value, '$at[$i]'),
          ],
        _ => node,
      };

  /// [_screen] for a step or setup entry, which leaves the `text` of a
  /// `fill` or `type` as it is: the one place a secret may go.
  Object? _screenEntry(Object? raw, String where) {
    if (raw is! Map<Object?, Object?>) return _screen(raw, where);
    return <Object?, Object?>{
      for (final MapEntry<Object?, Object?>(:Object? key, :Object? value)
          in raw.entries)
        key: (key == 'fill' || key == 'type') && value is Map<Object?, Object?>
            ? <Object?, Object?>{
                for (final MapEntry<Object?, Object?>(
                      key: Object? arg,
                      value: Object? given,
                    ) in value.entries)
                  arg: arg == 'text'
                      ? given
                      : _screen(given, '$where.$key.$arg'),
              }
            : _screen(value, '$where.$key'),
    };
  }

  /// Reports [value], the secret [what] names, at [at] when it is shorter
  /// than [kPerfMinSecretLength]. Names the length, never the value.
  void _refuseShortSecret(String value, String at, String what) {
    final int length = value.length;
    if (length >= kPerfMinSecretLength) return;
    _unmasked.add(
      '$at: $what is $length character${length == 1 ? '' : 's'}; a secret '
      'shorter than $kPerfMinSecretLength would be masked wherever its text '
      'appears, inside every number and word of every log line, so give it a '
      'longer value.',
    );
  }

  String _refuseSecret(String at) {
    problems.add(
      'a secret may only be typed: $at takes a value from \${env.*} or a '
      'secret param, and only the text of a fill or type may.',
    );
    return '***';
  }

  // -------------------------------------------------------------------------
  // Keys and lists
  // -------------------------------------------------------------------------

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

  /// Appends the entries of [raw], a list at [at] in [frame]'s file, to
  /// [out], an include flattened in place.
  void _setupList(
    Object? raw,
    String at,
    Set<PerfPlatform> platforms,
    _Frame frame,
    List<PerfSetupStep> out,
  ) {
    if (raw is! List<Object?>) {
      problems.add('${frame.at(at)} must be a list.');
      return;
    }
    for (final (int i, Object? entry) in raw.indexed) {
      final String where = frame.at('$at[$i]');
      if (entry is Map<Object?, Object?> && entry.containsKey('include')) {
        _include(entry, where, platforms, frame, out);
        continue;
      }
      final PerfSetupStep? step = _setupStep(entry, where, platforms);
      if (step != null) out.add(step._placed(where, frame.guard));
    }
  }

  PerfSetupStep? _setupStep(
    Object? raw,
    String where,
    Set<PerfPlatform> platforms,
  ) {
    raw = _screenEntry(raw, where);
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

  List<PerfStep> _steps(
    Object? raw,
    String at,
    Set<PerfPlatform> platforms,
  ) {
    if (raw is! List<Object?> || raw.isEmpty) {
      problems.add('$at must be a non-empty list: a session that drives '
          'nothing draws no frames and perf_end refuses it.');
      return const <PerfStep>[];
    }
    final List<PerfStep> steps = <PerfStep>[];
    for (int i = 0; i < raw.length; i++) {
      final Object? entry = raw[i];
      if (entry is Map<Object?, Object?> && entry.containsKey('include')) {
        problems.add('$at[$i]: include is a setup entry; the measured steps '
            'are written out, so the file shows everything the window times.');
        continue;
      }
      final PerfStep? step = _step(entry, '$at[$i]', platforms);
      if (step != null) steps.add(step);
    }
    return steps;
  }

  PerfStep? _step(Object? raw, String where, Set<PerfPlatform> platforms) {
    raw = _screenEntry(raw, where);
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
      final String wheelHint = verb == PerfStepVerb.wheel
          ? ', and a drag with `only: [android, ios]` to scroll there'
          : '';
      problems.add(
        '$where: ${verb.wire} drives Chrome DevTools and would run on $others. '
        'Add `only: [chrome]`$wheelHint.',
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
    final Object? given = args['text'];
    final bool secret = typing && given is _Secret;
    final String? text = typing
        ? _string(given is _Secret ? given.value : given, '$at.text')
        : null;
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
      secret: secret,
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

/// Parses [source] into the map a scenario file is; throws otherwise.
Map<Object?, Object?> _scenarioDocument(String source) {
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
  return document;
}

/// A string any part of which came from `${env.*}` or a `secret: true`
/// param. It prints as `***`, so a problem that quotes one leaks nothing.
final class _Secret {
  const _Secret(this.value);

  final String value;

  @override
  String toString() => '***';
}

/// The keys a variant may replace.
const Set<String> _kVariantKeys = <String>{
  'viewport',
  'platforms',
  'repeat',
  'steps',
};

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
