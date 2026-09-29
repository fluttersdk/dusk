part of 'scenario.dart';

/// What [loadPerfScenarios] read: the file expanded by its variants (one
/// scenario when it has none), and every tainted value met while loading,
/// for a caller to build its redactor from.
typedef PerfLoadResult = ({List<PerfScenario> scenarios, Set<String> secrets});

/// What [loadPerfSetup] read: the flattened entries and the tainted values.
typedef PerfSetupLoadResult = ({
  List<PerfSetupStep> setup,
  Set<String> secrets,
});

/// Loads the scenario file at [path] with its fragments and variants.
///
/// A setup entry `- include: <path>` (relative to the including file) with
/// an optional `with: {param: value}` and `when: {text, unless_text,
/// timeout_ms}` is flattened into `setup` in place; a fragment is a map of
/// `params: {name: {secret: bool, default: value}}`, an optional `when:` and
/// `steps:` in the setup grammar, nested includes allowed up to
/// [kPerfMaxIncludeDepth] deep. Every scalar value is interpolated once in
/// its own file: `${name}` reads the fragment's params, `${env.NAME}` reads
/// [env], `$$` is a literal `$`.
///
/// A value from `${env.*}` or a `secret: true` param is a secret: it may
/// only be the `text` of a `fill` or `type`, where the step is marked
/// [PerfStep.secret], and it never appears in a problem.
///
/// `variants: {<key>: {viewport, platforms, repeat, steps}}` yields one
/// scenario per key, named `<name>-<key>`, each key replacing the base's.
///
/// Throws [PerfScenarioException] listing every problem, and the
/// [FileSystemException] of a scenario file it cannot read (a fragment it
/// cannot read is a problem of the file including it).
Future<PerfLoadResult> loadPerfScenarios(
  String path, {
  Map<String, String> env = const <String, String>{},
}) async {
  final String file = _absolutePath(path);
  final Map<Object?, Object?> document =
      _scenarioDocument(await File(file).readAsString());
  final _ScenarioReader reader = _ScenarioReader(env: env, file: file);
  final List<PerfScenario> scenarios = reader.readScenarios(document);
  return (
    scenarios: scenarios,
    secrets: Set<String>.unmodifiable(reader.secrets)
  );
}

/// Loads a bare list of setup entries written in the file at [path], such
/// as a campaign's `after_start:`, with the grammar a scenario's `setup`
/// has, includes and all.
///
/// [entries] is the list as `loadYaml` answered it, not yet interpolated:
/// it is interpolated here, once, against [env]. [at] names the list in
/// problems and origins (`after_start[0]`), and [platforms] are the ones a
/// gesture's `only:` and the Chrome-only rule are checked against. A null
/// [entries] is an empty list. Throws [PerfScenarioException].
PerfSetupLoadResult loadPerfSetup(
  Object? entries, {
  required String path,
  required String at,
  Map<String, String> env = const <String, String>{},
  Set<PerfPlatform>? platforms,
}) {
  final _ScenarioReader reader = _ScenarioReader(
    env: env,
    file: _absolutePath(path),
  );
  final List<PerfSetupStep> setup = reader.readSetup(
    entries,
    at,
    platforms ?? PerfPlatform.values.toSet(),
  );
  return (setup: setup, secrets: Set<String>.unmodifiable(reader.secrets));
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Where a list of setup entries is being read: the file (null for a
/// string), how its locations are prefixed, the includes that led here and
/// the guard they put the entries under.
final class _Frame {
  const _Frame({
    required this.file,
    required this.chain,
    this.label = '',
    this.depth = 0,
    this.guard,
  });

  final String? file;

  /// Empty for the file being loaded, so its locations read `setup[2]` as
  /// they always have; the fragment's shown path otherwise.
  final String label;

  final int depth;

  /// The absolute paths from the loaded file down to [file].
  final List<String> chain;

  final PerfSetupGuard? guard;

  String at(String path) => label.isEmpty ? path : '$label $path';
}

/// A fragment param name: what `${name}` can read.
final RegExp _kParamName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

const Set<String> _kIncludeKeys = <String>{'include', 'with', 'when'};
const Set<String> _kFragmentKeys = <String>{'params', 'when', 'steps'};
const Set<String> _kParamKeys = <String>{'secret', 'default'};
const Set<String> _kWhenKeys = <String>{'text', 'unless_text', 'timeout_ms'};

String _absolutePath(String path) =>
    Uri.file(File(path).absolute.path).normalizePath().toFilePath();

/// [include] resolved against the directory of [from].
String _resolvePath(String from, String include) =>
    Uri.file(from).resolveUri(Uri.file(include)).toFilePath();

/// The fragments and their guards.
extension on _ScenarioReader {
  /// Flattens the include [entry] at [where] into [out].
  void _include(
    Map<Object?, Object?> entry,
    String where,
    Set<PerfPlatform> platforms,
    _Frame frame,
    List<PerfSetupStep> out,
  ) {
    final int before = problems.length;

    // 1. The entry: a path, what to pass and when to run. `with:` values
    //    pass as they are, secrets included; the fragment decides where
    //    they may go.
    for (final Object? key in entry.keys) {
      if (!_kIncludeKeys.contains(key)) {
        problems.add('$where: unknown include key "$key"; allowed: '
            '${_kIncludeKeys.join(', ')}.');
      }
    }
    final String? path = _string(
      _screen(entry['include'], '$where.include'),
      '$where.include',
    );
    final Object given = entry['with'] ?? const <Object?, Object?>{};
    if (given is! Map<Object?, Object?>) {
      problems.add('$where.with must be a map of param: value.');
    }
    final String? from = frame.file;
    if (from == null) {
      problems.add("$where.include: an include resolves against the "
          "including file's path, and a scenario parsed from a string has "
          'none; load the file with loadPerfScenarios.');
      return;
    }
    if (path == null || given is! Map<Object?, Object?>) return;
    if (problems.length > before) return;

    // 2. Where it points, and whether following it loops or runs too deep.
    final String target = _resolvePath(from, path);
    final String shown = _shown(target);
    if (frame.chain.contains(target)) {
      problems.add('$where.include: include cycle '
          '${<String>[...frame.chain, target].map(_shown).join(' -> ')}.');
      return;
    }
    if (frame.depth >= kPerfMaxIncludeDepth) {
      problems.add('$where.include: includes nest deeper than '
          '$kPerfMaxIncludeDepth (${frame.chain.map(_shown).join(' -> ')} '
          '-> $shown).');
      return;
    }

    // 3. The fragment, its params filled from `with:`.
    final Map<Object?, Object?>? fragment = _fragment(target, shown, where);
    if (fragment == null) return;
    final Map<String, Object>? scope =
        _scope(fragment['params'], given, shown, where);
    if (scope == null) return;

    // 4. Its guard: the include's own, else the fragment's, read in the
    //    fragment's scope.
    PerfSetupGuard? guard = frame.guard;
    final Object? when =
        entry['when'] ?? _plain(fragment['when'], scope, shown, 'when');
    if (when != null) {
      guard = _guard(
        when,
        entry['when'] != null ? '$where.when' : '$shown when',
        origin: where,
        parent: frame.guard,
      );
      if (guard == null) return;
    }

    // 5. Its steps, read in its scope and flattened here.
    final Object? steps = _plain(fragment['steps'], scope, shown, 'steps');
    if (steps is! List<Object?> || steps.isEmpty) {
      problems.add('$shown steps must be a non-empty list of setup entries.');
      return;
    }
    _setupList(
      steps,
      'steps',
      platforms,
      _Frame(
        file: target,
        label: shown,
        depth: frame.depth + 1,
        chain: <String>[...frame.chain, target],
        guard: guard,
      ),
      out,
    );
  }

  /// The fragment file at [target]; null after reporting why it is not one.
  Map<Object?, Object?>? _fragment(String target, String shown, String where) {
    final Object? document;
    try {
      document = loadYaml(File(target).readAsStringSync());
    } on FileSystemException catch (e) {
      problems.add('$where.include: cannot read $shown '
          '(${e.osError?.message ?? e.message}).');
      return null;
    } on YamlException catch (e) {
      problems.add('$shown: not valid YAML: ${e.message}');
      return null;
    }
    if (document is! Map<Object?, Object?>) {
      problems.add('$shown must be a map of ${_kFragmentKeys.join(', ')}.');
      return null;
    }
    final Iterable<Object?> unknown =
        document.keys.where((Object? k) => !_kFragmentKeys.contains(k));
    for (final Object? key in unknown) {
      problems.add('$shown: unknown key "$key"; allowed: '
          '${_kFragmentKeys.join(', ')}.');
    }
    return unknown.isEmpty ? document : null;
  }

  /// The params of the fragment [shown], from [given] (already interpolated
  /// in the caller's scope, so never scanned again) or their defaults (read
  /// in [env] alone). A secret param's value becomes a [_Secret]. Null after
  /// reporting a problem.
  Map<String, Object>? _scope(
    Object? raw,
    Map<Object?, Object?> given,
    String shown,
    String where,
  ) {
    final int before = problems.length;
    final Map<Object?, Object?> params =
        raw is Map<Object?, Object?> ? raw : const <Object?, Object?>{};
    if (raw != null && raw is! Map<Object?, Object?>) {
      problems.add('$shown params must be a map of name: {secret, default}.');
    }
    final Map<String, Object> scope = <String, Object>{};
    for (final MapEntry<Object?, Object?>(:Object? key, :Object? value)
        in params.entries) {
      // 1. The declaration.
      final String name = '$key';
      final String at = '$shown params.$name';
      if (!_kParamName.hasMatch(name)) {
        problems.add('$at: a param name is a letter or _, then letters, '
            'digits or _.');
        continue;
      }
      final Object spec = value ?? const <Object?, Object?>{};
      if (spec is! Map<Object?, Object?>) {
        problems.add('$at must be a map of ${_kParamKeys.join(', ')}.');
        continue;
      }
      for (final Object? k in spec.keys) {
        if (!_kParamKeys.contains(k)) {
          problems.add('$at: unknown key "$k"; allowed: '
              '${_kParamKeys.join(', ')}.');
        }
      }
      final Object secret = spec['secret'] ?? false;
      if (secret is! bool) problems.add('$at.secret must be true or false.');

      // 2. The value: what the include passed, else the default.
      final Object? filled;
      if (given.containsKey(name)) {
        filled = _paramValue(given[name], '$where.with.$name');
      } else if (spec.containsKey('default')) {
        filled = _paramValue(
          _plain(spec['default'], const <String, Object>{}, shown,
              'params.$name.default'),
          '$at.default',
        );
      } else {
        problems.add('$where: $shown needs $name, a param without a default.');
        continue;
      }
      if (filled == null) continue;
      final Object bound =
          secret == true && filled is String ? _Secret(filled) : filled;
      if (bound is _Secret && bound.value.isNotEmpty) secrets.add(bound.value);
      scope[name] = bound;
    }

    // 3. Anything passed that the fragment does not declare.
    for (final Object? key in given.keys) {
      if (!params.containsKey(key)) {
        problems.add('$where.with.$key: unknown param; $shown declares '
            '${params.isEmpty ? 'none' : params.keys.join(', ')}.');
      }
    }
    return problems.length > before ? null : scope;
  }

  /// A param value as the opaque string `${name}` substitutes.
  Object? _paramValue(Object? value, String at) => switch (value) {
        String() || _Secret() => value,
        num() || bool() => '$value',
        _ => _refuseParamValue(at),
      };

  Object? _refuseParamValue(String at) {
    problems.add('$at must be a string, a number or a boolean.');
    return null;
  }

  /// The `when:` [raw] at [at]; null after reporting a problem.
  PerfSetupGuard? _guard(
    Object? raw,
    String at, {
    required String origin,
    required PerfSetupGuard? parent,
  }) {
    final Object? when = _screen(raw, at);
    if (when is! Map<Object?, Object?>) {
      problems.add('$at must be a map of ${_kWhenKeys.join(', ')}.');
      return null;
    }
    for (final Object? key in when.keys) {
      if (!_kWhenKeys.contains(key)) {
        problems.add('$at: unknown key "$key"; allowed: '
            '${_kWhenKeys.join(', ')}.');
      }
    }
    final String? text = _string(when['text'], '$at.text');
    final Object? unless = when['unless_text'];
    final String? unlessText =
        unless == null ? null : _string(unless, '$at.unless_text');
    final int? timeoutMs = when['timeout_ms'] == null
        ? kPerfWhenTimeoutMs
        : _positiveInt(when['timeout_ms'], '$at.timeout_ms');
    if (text == null ||
        timeoutMs == null ||
        (unless != null && unlessText == null)) {
      return null;
    }
    return PerfSetupGuard(
      text: text,
      unlessText: unlessText,
      timeoutMs: timeoutMs,
      origin: origin,
      parent: parent,
    );
  }

  /// [target] as problems and origins show it: relative to the directory
  /// of the file being loaded when it is under it.
  String _shown(String target) {
    final String dir = File(file!).parent.path;
    final String prefix = dir.endsWith(Platform.pathSeparator)
        ? dir
        : '$dir${Platform.pathSeparator}';
    return target.startsWith(prefix) ? target.substring(prefix.length) : target;
  }
}
