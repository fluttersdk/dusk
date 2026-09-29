import 'dart:convert';

import 'perf_actions.dart';
import 'perf_redaction.dart';
import 'perf_run_driver.dart';
import 'perf_support.dart';
import 'scenario.dart';

/// The longest single in-app wait: well under the 10 s after which DWDS
/// abandons a service extension call on the web.
const int _kWaitSliceMs = 5000;

/// How long a setup navigate waits for the app to mount a Router. The boot
/// id answers from `main()`, which can still be awaiting its own boot or be
/// showing a loading screen before `runApp` builds the router.
const Duration _kRouterBudget = Duration(seconds: 10);

/// The most `ext.dusk.get_routes` reads that wait gets, so the budget holds
/// on a driver whose pause returns at once.
const int _kRouterMaxPolls = 100;

/// How often a `when` guard looks at the screen while it waits.
const Duration _kWhenPollInterval = Duration(milliseconds: 250);

/// How many `ext.dusk.exceptions` entries a setup failure quotes.
const int _kDiagnosticExceptions = 3;

/// The longest exception message a setup failure quotes, in characters.
const int _kDiagnosticMessageChars = 200;

/// Runs a list of setup entries against the app: a scenario's `setup`
/// before every repeat, or a campaign's `after_start` once per cold start.
///
/// Every failure but a restart's is a [PerfRunException] that ends with
/// [diagnose]: the route the app is on, the last navigate's payload and the
/// newest exceptions, since "did not appear" alone does not say which screen
/// it did not appear on.
final class PerfSetupRunner {
  PerfSetupRunner(this.actions, {this.viewport, this.redactor});

  final PerfActions actions;

  /// Masks an exception message [diagnose] quotes before it is cut: a mask
  /// applied after the cut no longer matches a secret the cut split, and
  /// leaves its prefix behind. Null quotes messages as the app sent them.
  final PerfRedactor? redactor;

  /// The Chrome viewport applied before the first entry and again after
  /// every `hot_restart`, which drops it; null leaves the page as it is.
  final ({int width, int height})? viewport;

  /// The payload of the current pass's last honored navigate, for
  /// [diagnose]; null before the first.
  Map<String, dynamic>? _lastNavigate;

  /// Runs [setup] once, in order. [where] names the list's owner in every
  /// failure (a scenario's name), each entry after it by its origin:
  /// `list-scroll setup[2] (navigate)`.
  ///
  /// Answers whether a navigate landed only after `ext.dusk.navigate`
  /// answered false, which the unit's repeat records as `setupLandedLate`.
  /// Throws [PerfRunException].
  ///
  /// An entry under `when` guards runs only when each guard in its chain
  /// decided to run. A guard is decided once per call, outermost first, at
  /// the first entry that carries it and would run on this platform
  /// ([_decide]); the decision covers every entry flattened out of its
  /// include, told apart by identity.
  Future<({bool landedLate})> run(
    List<PerfSetupStep> setup,
    String where,
  ) async {
    _lastNavigate = null;
    bool landedLate = false;
    final Map<PerfSetupGuard, bool> decided =
        Map<PerfSetupGuard, bool>.identity();
    await actions.viewport(viewport);
    for (final (int i, PerfSetupStep step) in setup.indexed) {
      // 1. A gesture limited to another platform neither runs nor spends a
      //    guard: the group's first step that does run decides it.
      final PerfStep? gesture = step.gesture;
      if (gesture != null && !gesture.runsOn(actions.env.platform)) continue;

      // 2. Its guards, outermost first; a skipped one skips everything under
      //    it, so an inner guard it covers is never polled.
      if (!await _guardsAllow(step.guard, where, decided)) continue;

      // 3. A restart names the app's last answer itself, and an app that is
      //    not back has nothing to diagnose with.
      if (step.verb == PerfSetupVerb.hotRestart) {
        await actions.driver.restart();
        await actions.viewport(viewport);
        continue;
      }

      // 4. Everything else says where the app was when it failed.
      final String label = '$where ${step.origin ?? 'setup[$i]'} '
          '(${gesture?.verb.wire ?? step.verb.wire})';
      try {
        if (await _step(step, label)) landedLate = true;
      } on Exception catch (e) {
        throw PerfRunException(
          '${e is PerfRunException ? e.message : '$label: $e'}\n'
          '${await diagnose()}',
        );
      }
    }
    return (landedLate: landedLate);
  }

  /// Whether every guard from [innermost] out to its root decided to run,
  /// deciding each one still open in [decided] (outermost first). Throws
  /// [PerfRunException] with [diagnose] when a guard times out with an
  /// `unless_text` set.
  Future<bool> _guardsAllow(
    PerfSetupGuard? innermost,
    String where,
    Map<PerfSetupGuard, bool> decided,
  ) async {
    final List<PerfSetupGuard> chain = <PerfSetupGuard>[
      for (PerfSetupGuard? g = innermost; g != null; g = g.parent) g,
    ];
    for (final PerfSetupGuard guard in chain.reversed) {
      bool? runs = decided[guard];
      if (runs == null) {
        final String label = '$where ${guard.origin} (when)';
        try {
          runs = await _decide(guard, label);
        } on PerfRunException catch (e) {
          throw PerfRunException('${e.message}\n${await diagnose()}');
        }
        decided[guard] = runs;
      }
      if (!runs) return false;
    }
    return true;
  }

  /// Polls `ext.dusk.find --text` every [_kWhenPollInterval] for up to
  /// [PerfSetupGuard.timeoutMs]: true once [PerfSetupGuard.text] shows,
  /// false once [PerfSetupGuard.unlessText] shows (checked first, so it wins
  /// when both do), and false on timeout when there is no `unless_text`.
  ///
  /// Throws [PerfRunException] prefixed with [where] on a timeout with an
  /// `unless_text`: the screen showed neither the state the group needs nor
  /// the one it produces, so running on would measure the wrong screen.
  Future<bool> _decide(PerfSetupGuard guard, String where) async {
    final Duration budget = Duration(milliseconds: guard.timeoutMs);
    final int maxPolls =
        guard.timeoutMs ~/ _kWhenPollInterval.inMilliseconds + 1;
    final Stopwatch clock = Stopwatch()..start();
    for (int poll = 1;; poll++) {
      final String? unless = guard.unlessText;
      if (unless != null && await _shows(unless, where)) return false;
      if (await _shows(guard.text, where)) return true;
      if (poll >= maxPolls || clock.elapsed >= budget) break;
      await actions.driver.pause(_kWhenPollInterval);
    }
    final String? unless = guard.unlessText;
    if (unless == null) return false;
    throw PerfRunException(
      '$where: neither "${guard.text}" nor "$unless" showed within '
      '${guard.timeoutMs} ms, so the screen is in neither the state the '
      'guarded steps need nor the one they produce.',
    );
  }

  /// Whether `ext.dusk.find --text` matches [text] on the screen right now.
  Future<bool> _shows(String text, String where) async =>
      (await actions.call(
        'ext.dusk.find',
        <String, String>{'text': text},
        where,
      ))['ref'] !=
      null;

  /// One entry other than `hot_restart`, which [run] runs itself. Answers
  /// whether it was a navigate that landed late. Throws [PerfRunException]
  /// prefixed with [where].
  Future<bool> _step(PerfSetupStep step, String where) async {
    switch (step.verb) {
      case PerfSetupVerb.hotRestart:
        throw StateError('run() runs hot_restart itself.');
      case PerfSetupVerb.gesture:
        try {
          await actions.drive(step.gesture!, record: false);
        } on Exception catch (e) {
          throw PerfRunException(
            '$where: ${e is PerfRunException ? e.message : e}',
          );
        }
      case PerfSetupVerb.navigate:
        return _navigate(step.argument!, where);
      case PerfSetupVerb.waitForText:
        // In slices: DWDS cuts any service extension call at 10 s and
        // answers -32603, so one in-app wait of the whole budget died on
        // every slow web restart. Each slice is a full in-app wait; the
        // budget is spent slice by slice rather than by the host clock.
        bool matched = false;
        final int budget = step.timeoutMs ?? kPerfWaitForTextTimeoutMs;
        for (int left = budget; left > 0 && !matched;) {
          final int slice = left < _kWaitSliceMs ? left : _kWaitSliceMs;
          final Map<String, dynamic> result = await actions.call(
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
        await actions.call(
          'ext.dusk.wait_for_network_idle',
          const <String, String>{},
          where,
        );
    }
    return false;
  }

  /// Navigates to [route] and holds the app to it; answers whether it
  /// landed only after `ext.dusk.navigate` answered false.
  ///
  /// The app has to be routable first ([awaitRouter]). A `navigated: false`
  /// then fails with the payload unless the route lands within
  /// [kPerfResolveBudget] ([_awaitLanding]): a dropped route never lands and
  /// a redirected one lands elsewhere, and every later step would run on the
  /// wrong screen. The router's URI read right after is read again once the
  /// network is idle, since a first fetch that answers 401 redirects away
  /// afterwards. The two reads compare paths: a page that normalises its
  /// query after the first fetch (`/monitors` to `/monitors?page=1`) has not
  /// moved.
  Future<bool> _navigate(String route, String where) async {
    // 1. A navigate is verified against the mounted Router, so one sent
    //    before the Router exists answers false even when it lands later.
    await awaitRouter(where);

    // 2. The router has to honor the route, if not within the navigate's
    //    own two-frame read then shortly after it.
    bool landedLate = false;
    Map<String, dynamic> payload = await actions.call(
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
      landedLate = true;
    }
    _lastNavigate = payload;

    // 3. And the app has to stay there once its first fetches are done.
    final Object? landed = (await actions.call(
      'ext.dusk.get_routes',
      const <String, String>{},
      where,
    ))['uri'];
    await actions.call(
      'ext.dusk.wait_for_network_idle',
      const <String, String>{},
      where,
    );
    final Object? settled = (await actions.call(
      'ext.dusk.get_routes',
      const <String, String>{},
      where,
    ))['uri'];
    Object? path(Object? uri) => uri is String ? _routePath(uri) : uri;
    if (path(settled) != path(landed)) {
      throw PerfRunException(
        '$where: navigating to "$route" landed on "$landed", and once the '
        'network was idle the app had moved to "$settled".',
      );
    }
    return landedLate;
  }

  /// Whether the Router's `uri` reaches [route]'s path exactly, query ignored,
  /// within [kPerfResolveBudget], read every [kPerfResolvePollInterval] and at
  /// most [kPerfResolveMaxPolls] times.
  ///
  /// Exact, unlike the prefix match `ext.dusk.navigate` makes: a web hot
  /// restart keeps the URL, so an app left on `/monitors/7` would pass a
  /// prefix check for a dropped navigate to `/monitors`. A setup navigate
  /// names its screen.
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
      final Object? uri = (await actions.call(
        'ext.dusk.get_routes',
        const <String, String>{},
        where,
      ))['uri'];
      if (uri is String) {
        if (_routePath(uri) == wanted) return true;
      }
      if (poll >= kPerfResolveMaxPolls || clock.elapsed >= kPerfResolveBudget) {
        return false;
      }
      await actions.driver.pause(kPerfResolvePollInterval);
    }
  }

  /// Waits until `ext.dusk.get_routes` reports a mounted Router's `uri`,
  /// read every [kPerfResolvePollInterval] for up to 10 s (and at most 100
  /// reads).
  ///
  /// `ext.dusk.boot_id` answers once `DuskPlugin.install()` has run, and a
  /// host that installs dusk before its own boot (magic_devtools' documented
  /// order) or shows a loading screen first has no Router yet. A setup
  /// navigate waits here rather than the restart, which keeps a scenario that
  /// never navigates, or an app with no Router at all, free of it.
  ///
  /// Throws [PerfRunException] prefixed with [where] when the budget runs out,
  /// or at once when the answer has no `uri` key: the app runs a dusk older
  /// than this CLI.
  Future<void> awaitRouter(String where) async {
    final Stopwatch clock = Stopwatch()..start();
    for (int poll = 1;; poll++) {
      final Map<String, dynamic> routes = await actions.call(
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
      await actions.driver.pause(kPerfResolvePollInterval);
    }
  }

  /// One line on where the app is: its route, the last navigate of the
  /// current pass and its newest exceptions. A diagnostic call that fails is
  /// named in place of its answer: the failure it explains stands either way.
  Future<String> diagnose() async {
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
        final List<dynamic> entries = perfList(r['exceptions']);
        if (entries.isEmpty) return 'last exceptions: none';
        return 'last exceptions: ${entries.map(_exceptionLine).join(' | ')}';
      },
    );
    return 'Diagnostics: $route; $navigate; $exceptions.';
  }

  /// One `ext.dusk.exceptions` entry as a setup failure quotes it: the type,
  /// the first line of the message, masked and then cut to
  /// [_kDiagnosticMessageChars], and when it happened.
  String _exceptionLine(Object? entry) {
    final Map<String, dynamic> e = perfMap(entry);
    final String line = '${e['message'] ?? ''}'.split('\n').first;
    final String message = redactor?.redact(line) ?? line;
    final String cut = message.length > _kDiagnosticMessageChars
        ? '${message.substring(0, _kDiagnosticMessageChars)}...'
        : message;
    return '${e['type']}: $cut${e['time'] == null ? '' : ' at ${e['time']}'}';
  }

  Future<String> _describe(
    String method,
    Map<String, String> params,
    String Function(Map<String, dynamic> result) render,
  ) async {
    try {
      return render(await actions.driver.call(method, params));
    } on Exception catch (e) {
      return '$method failed ($e)';
    }
  }
}

/// The path of a route or a router URI, `/` when it has none.
String _routePath(String route) {
  final String path = Uri.tryParse(route)?.path ?? route;
  return path.isEmpty ? '/' : path;
}
