import 'dart:convert';

import '../commands/dusk_perf_run_command.dart';
import 'scenario.dart';

/// How long a target may take to show up before it "matched nothing": a
/// screen still settling after a navigate or a tap has not built it yet.
const Duration kPerfResolveBudget = Duration(seconds: 3);

/// The gap between two lookups of a target that has not shown up yet, and
/// between two reads of a Router a setup navigate waits on.
const Duration kPerfResolvePollInterval = Duration(milliseconds: 100);

/// The most lookups one target gets, so the budget holds on a driver whose
/// pause returns at once.
const int kPerfResolveMaxPolls = 30;

/// How many candidates a role target asks `ext.dusk.observe` for: every
/// interactive node on a screen, so an index deep in a list still resolves.
const int _kObserveLimit = 5000;

/// The gap between two ticks of one `wheel` step: one frame at 60 Hz.
const Duration _kWheelTickInterval = Duration(milliseconds: 16);

/// A target resolved before `perf_begin`, and the hover point when its step
/// is a wheel.
typedef PerfResolvedTarget = ({String ref, Map<String, dynamic>? point});

/// Drives one [PerfStep] or one extension call against the app, the part a
/// scenario's setup, its measured window and a campaign's `after_start` all
/// share.
///
/// Every target is resolved on the live screen at the moment it is needed,
/// and every action goes out with `includeSnapshot: false`: a snapshot per
/// step would build the semantics tree and cost frames nobody asked for.
final class PerfActions {
  PerfActions(this.driver, this.env);

  final PerfRunDriver driver;
  final PerfRunEnvironment env;

  bool get _chrome => env.platform == PerfPlatform.chrome;

  /// Calls [method] and answers its result; any failure becomes a
  /// [PerfRunException] prefixed with [where] and the method.
  Future<Map<String, dynamic>> call(
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

  /// Sets the page to [size] on Chrome; nothing elsewhere, or with no size.
  Future<void> viewport(({int width, int height})? size) async {
    if (!_chrome || size == null) return;
    await resize(size.width, size.height);
  }

  /// Overrides the page's viewport to [width] by [height] CSS pixels.
  Future<void> resize(int width, int height) => driver.cdp(
        'Emulation.setDeviceMetricsOverride',
        <String, dynamic>{
          'width': width,
          'height': height,
          // 0 keeps the browser's own device pixel ratio.
          'deviceScaleFactor': 0,
          'mobile': false,
        },
      );

  /// Drives [step] through the live tree. Returns the dispatch points when
  /// [record] asks for them and the verb has any, for the semantics pass to
  /// replay; null otherwise.
  ///
  /// The target is [resolved] when the caller resolved it earlier, else
  /// resolved here, and [onResolved] is handed the clock of that resolve.
  Future<Map<String, dynamic>?> drive(
    PerfStep step, {
    required bool record,
    PerfResolvedTarget? resolved,
    void Function(Stopwatch clock)? onResolved,
  }) async {
    const Map<String, String> quiet = <String, String>{
      'includeSnapshot': 'false',
    };
    final Map<String, String> report = <String, String>{
      if (record) 'reportPoint': 'true',
    };
    Future<String> target() async {
      final PerfResolvedTarget? early = resolved;
      if (early != null) return early.ref;
      final Stopwatch clock = Stopwatch()..start();
      final String ref = await resolve(step.target!);
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
            resolved?.point ?? await hover(await target());
        await wheel(point, step);
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
        await untargeted(step);
    }
    return null;
  }

  /// Runs a step that takes no target: `press_key`, `navigate`, `resize`,
  /// `wait`. Throws [StateError] for any other verb.
  Future<void> untargeted(PerfStep step) async {
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
        await resize(step.width!, step.height!);
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

  /// Hovers [ref] and answers the point it hovered: what a mouse does before
  /// it wheels, and where the wheel then goes.
  Future<Map<String, dynamic>> hover(String ref) async => _map(
        (await driver.call(
          'ext.dusk.hover',
          <String, String>{
            'ref': ref,
            'reportPoint': 'true',
            'includeSnapshot': 'false',
          },
        ))['point'],
      );

  /// Sends [PerfStep.ticks] wheel events at [point], one frame apart, the
  /// way a real wheel scrolls: a single large event jumps the list in one
  /// frame, and a session built on it measured five frames.
  Future<void> wheel(Map<String, dynamic> point, PerfStep step) async {
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

  /// Resolves [target] against the live tree now: a ref from an earlier
  /// repeat is stale after the restart.
  ///
  /// A target that is not there yet is looked up again every
  /// [kPerfResolvePollInterval] for up to [kPerfResolveBudget] (and at most
  /// [kPerfResolveMaxPolls] lookups) before it "matched nothing": a screen
  /// that is still building after a navigate or a tap has not drawn it yet.
  Future<String> resolve(PerfTarget target) async {
    final Stopwatch clock = Stopwatch()..start();
    for (int poll = 1;; poll++) {
      final String? ref = await lookup(target);
      if (ref != null) return ref;
      if (poll >= kPerfResolveMaxPolls || clock.elapsed >= kPerfResolveBudget) {
        throw PerfRunException(
          'target ${jsonEncode(target.toJson())} matched nothing on the live '
          'screen within ${kPerfResolveBudget.inSeconds} s ($poll lookups).',
        );
      }
      await driver.pause(kPerfResolvePollInterval);
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
  Future<String?> lookup(PerfTarget target) async =>
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

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<dynamic> _list(Object? value) =>
    value is List<dynamic> ? value : const <dynamic>[];
