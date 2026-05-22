import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show CheckedState, FlutterView, Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_wind_diagnostics_contracts/fluttersdk_wind_diagnostics_contracts.dart';

import '../dusk_plugin.dart';
import '../dusk_snapshot_enricher.dart';
import '../ref_registry.dart';
import '../utils/error_envelope.dart';

// ---------------------------------------------------------------------------
// MCP descriptor constants — consumed by DuskArtisanProvider.mcpTools()
// ---------------------------------------------------------------------------

/// MCP tool name for the structured candidate-list observer.
const String kDuskObserveMcpName = 'dusk_observe';

/// VM Service extension method name for the observer.
const String kDuskObserveMcpExtension = 'ext.dusk.observe';

// ---------------------------------------------------------------------------
// Enricher field-filter sets — used to project per-candidate enricher output.
// ---------------------------------------------------------------------------

/// Default-subset top-level enricher keys (the `includeEnrichers='true'`
/// projection). Keeps the payload small while preserving the four enrichers
/// that the agent actually branches on:
///
/// * `magicFormField` — the field name the agent should type into.
/// * `magicRoute` — current screen path; lets the agent skip a redundant
///   `dusk_get_routes` round-trip.
/// * `magicGateResult` — whether the user is allowed to act on the candidate.
/// * `wind` — visual context, but filtered to the cheap fields only (see
///   [_kDefaultWindKeys]).
const Set<String> _kDefaultEnricherKeys = <String>{
  'magicFormField',
  'magicRoute',
  'magicGateResult',
  'wind',
};

/// Default-subset wind sub-fields (the `includeEnrichers='true'` projection).
/// The full Wind diagnostics block (sourced via `fluttersdk_wind_diagnostics_contracts`)
/// exposes the 6 core fields including hex colours and per-state breakdowns;
/// the default subset keeps only the two that drive agent decisions
/// (breakpoint + active state).
const Set<String> _kDefaultWindKeys = <String>{
  'breakpoint',
  'states',
};

// ---------------------------------------------------------------------------
// Aggregator
// ---------------------------------------------------------------------------

/// Registers the `ext.dusk.observe` VM Service extension.
///
/// Idempotent via [registerExtensionIdempotent]. Call from
/// `registerAllDuskExtensions` once during `DuskPlugin.install`.
void registerObserveExtensions() {
  registerExtensionIdempotent(kDuskObserveMcpExtension, extDuskObserveHandler);
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/// Handler for the `ext.dusk.observe` VM Service extension.
///
/// Walks the live Semantics + Element tree once, finds every interactive node
/// (same role detection as `ext.dusk.snap` + `ext.dusk.find`), mints a `q<N>`
/// query handle for each via [RefRegistry.registerQuery], and returns a
/// structured JSON list. Stagehand's "observe-once-act-many" pattern WITHOUT
/// any server-side LLM call — the caller agent decides which refs to act on.
///
/// Params (all string-valued; the VM Service surface is string-only):
///
/// * `intent` (optional): free-form caller hint describing what the agent is
///   looking for (e.g. `'login form'`). NOT used server-side; accepted purely
///   so callers can record their intent alongside the request.
/// * `limit` (optional, default 50): maximum number of candidates to return.
/// * `roles` (optional): comma-separated list of roles to filter (e.g.
///   `'button,textbox'`). Each role matches the same vocabulary `ext.dusk.snap`
///   emits (`button`, `textbox`, `link`, `checkbox`, `heading`, `image`).
/// * `includeEnrichers` (optional, default `'true'`): one of `'true'`,
///   `'false'`, `'full'`. `'true'` projects the default subset
///   ([_kDefaultEnricherKeys]); `'full'` projects every enricher field;
///   `'false'` projects no enricher fields.
///
/// Response JSON:
/// ```json
/// {
///   "candidates": [
///     {
///       "ref": "q12",
///       "role": "button",
///       "label": "Submit",
///       "value": null,
///       "bounds": {"x": 100, "y": 200, "w": 80, "h": 36},
///       "isEnabled": true,
///       "isVisible": true,
///       "magicFormField": "email",
///       "wind": {"breakpoint": "lg", "states": "[hover]"}
///     }
///   ],
///   "count": 1
/// }
/// ```
Future<developer.ServiceExtensionResponse> extDuskObserveHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Parse params — every field is optional. Defaults: limit=50,
    //    includeEnrichers='true', roles=null (every role accepted).
    final int limit = _parseInt(params['limit']) ?? 50;
    final Set<String>? roleFilter = _parseRoles(params['roles']);
    final _EnricherMode mode = _parseEnricherMode(params['includeEnrichers']);

    // 2. Walk every pipeline owner's semantics tree (root + every child;
    //    Flutter test harness, Flutter web, and modern engine configs host
    //    the widget tree under a CHILD pipeline owner — mirrors the walk in
    //    ext_snapshot.dart / ext_find.dart / error_envelope.dart).
    final SemanticsHandle handle = WidgetsBinding.instance.ensureSemantics();
    try {
      final Map<RenderObject, Element> elementByRenderObject =
          _buildElementByRenderObject();
      final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[];

      void visitNode(SemanticsNode node) {
        if (candidates.length >= limit) return;
        final SemanticsData data = node.getSemanticsData();
        final String? role = _roleFor(data);
        if (role != null && _isInteractive(data)) {
          if (roleFilter == null || roleFilter.contains(role)) {
            final Map<String, dynamic>? entry = _buildCandidate(
              node: node,
              data: data,
              role: role,
              elementByRenderObject: elementByRenderObject,
              mode: mode,
            );
            if (entry != null) {
              candidates.add(entry);
            }
          }
        }
        node.visitChildren((SemanticsNode child) {
          visitNode(child);
          return candidates.length < limit;
        });
      }

      void visitOwner(PipelineOwner owner) {
        if (candidates.length >= limit) return;
        final SemanticsNode? root = owner.semanticsOwner?.rootSemanticsNode;
        if (root != null) visitNode(root);
        owner.visitChildren((PipelineOwner child) {
          if (candidates.length < limit) visitOwner(child);
        });
      }

      visitOwner(RendererBinding.instance.rootPipelineOwner);

      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, dynamic>{
          'candidates': candidates,
          'count': candidates.length,
        }),
      );
    } finally {
      handle.dispose();
    }
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.observe: unexpected error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.observe: $e',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Candidate construction
// ---------------------------------------------------------------------------

/// Builds a single candidate JSON entry for [node]. Returns `null` when the
/// node cannot be backed by a live [Element] (no matching render object) —
/// such nodes are silently skipped, mirroring the snapshot walker.
Map<String, dynamic>? _buildCandidate({
  required SemanticsNode node,
  required SemanticsData data,
  required String role,
  required Map<RenderObject, Element> elementByRenderObject,
  required _EnricherMode mode,
}) {
  final RenderObject? renderObject = _renderObjectFor(node);
  if (renderObject == null) return null;
  final Element? element = elementByRenderObject[renderObject];
  if (element == null) return null;

  final Rect rect = _globalRectFor(renderObject);
  final bool isEnabled = data.flagsCollection.isEnabled != Tristate.isFalse;
  final bool isVisible = _isVisible(rect);

  // Mint a q-ref by deriving the most stable predicate available from the
  // semantics data. Prefer the semantics label (covers buttons + labelled
  // inputs); fall back to text-data via the same field; if neither is
  // available, the predicate carries an empty text — the action handler will
  // then surface a stale-handle error when it re-walks, which is the correct
  // behaviour (the candidate had no stable identity to begin with).
  final DuskQuery query = DuskQuery(
    semanticsLabel: data.label.isNotEmpty ? data.label : null,
    text: data.label.isEmpty && data.value.isNotEmpty ? data.value : null,
  );
  final String ref = RefRegistry.registerQuery(query);

  final Map<String, dynamic> candidate = <String, dynamic>{
    'ref': ref,
    'role': role,
    'label': data.label,
    'value': data.value.isEmpty ? null : data.value,
    'bounds': <String, dynamic>{
      'x': rect.left,
      'y': rect.top,
      'w': rect.width,
      'h': rect.height,
    },
    'isEnabled': isEnabled,
    'isVisible': isVisible,
  };

  // Merge enricher-projected fields per mode. Off => emit nothing extra.
  if (mode != _EnricherMode.off) {
    _mergeEnricherFields(candidate, element, mode);
  }

  return candidate;
}

// ---------------------------------------------------------------------------
// Enricher projection
// ---------------------------------------------------------------------------

/// Mode-controlled inclusion of enricher fields per candidate.
enum _EnricherMode {
  /// `includeEnrichers='false'` — emit no enricher fields at all.
  off,

  /// `includeEnrichers='true'` (default) — emit the default subset only.
  defaults,

  /// `includeEnrichers='full'` — emit every enricher field.
  full,
}

_EnricherMode _parseEnricherMode(String? raw) {
  if (raw == null || raw.isEmpty) return _EnricherMode.defaults;
  if (raw == 'false' || raw == '0') return _EnricherMode.off;
  if (raw == 'full') return _EnricherMode.full;
  return _EnricherMode.defaults;
}

/// Runs every registered enricher against [element], parses each fragment
/// into key/value pairs, and merges them into [candidate].
///
/// Fragment shapes follow the YAML conventions used by `ext.dusk.snap`:
///
/// * Single-line: `"key: value"` — top-level scalar field.
/// * Multi-line: first line is `"key:"`, every subsequent indented line is
///   `"  subKey: subValue"` — nested object field.
///
/// In [_EnricherMode.defaults] only [_kDefaultEnricherKeys] survive at the
/// top level, and `wind` sub-fields are filtered to [_kDefaultWindKeys].
void _mergeEnricherFields(
  Map<String, dynamic> candidate,
  Element element,
  _EnricherMode mode,
) {
  // Wind diagnostics via fluttersdk_wind_diagnostics_contracts neutral bridge.
  // Wind registers a WindDebugResolver at app boot (Wind.installDebugResolver);
  // observe reads it here without ever importing wind types. Mirrors the
  // additive walk in ext_snapshot.dart so the `wind:` block survives in
  // observe output after alpha-10's enricher removal.
  final WindDebugResolver? resolver = WindDebugRegistry.current;
  if (resolver != null) {
    final Map<String, Object?> windData = resolver.resolve(element);
    if (windData.isNotEmpty &&
        (mode != _EnricherMode.defaults ||
            _kDefaultEnricherKeys.contains('wind'))) {
      final Map<String, dynamic> filteredChildren = <String, dynamic>{};
      windData.forEach((String subKey, Object? subValue) {
        if (mode == _EnricherMode.defaults &&
            !_kDefaultWindKeys.contains(subKey)) {
          return;
        }
        filteredChildren[subKey] =
            subValue is List ? subValue.join(', ') : subValue?.toString() ?? '';
      });
      if (filteredChildren.isNotEmpty) {
        candidate.putIfAbsent('wind', () => filteredChildren);
      }
    }
  }
  // Existing enricher loop UNCHANGED (Magic still uses this path).
  for (final DuskSnapshotEnricher enricher in DuskPlugin.enrichers) {
    final String? fragment = enricher(element, RefRegistry.instance);
    if (fragment == null || fragment.isEmpty) continue;

    final List<String> lines = const LineSplitter()
        .convert(fragment.trimRight())
        .where((String l) => l.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) continue;

    final _ParsedFragment parsed = _parseFragment(lines);
    if (parsed.key.isEmpty) continue;
    if (mode == _EnricherMode.defaults &&
        !_kDefaultEnricherKeys.contains(parsed.key)) {
      continue;
    }

    if (parsed.children.isEmpty) {
      // Scalar field — emit only when the enricher did not already place one
      // (first-write-wins convention; matches snapshot dispatcher YAML
      // semantics).
      candidate.putIfAbsent(parsed.key, () => parsed.value);
    } else {
      // Nested object — wind / future grouped fields.
      final Map<String, dynamic> filteredChildren = <String, dynamic>{};
      parsed.children.forEach((String subKey, String subValue) {
        if (mode == _EnricherMode.defaults &&
            parsed.key == 'wind' &&
            !_kDefaultWindKeys.contains(subKey)) {
          return;
        }
        filteredChildren[subKey] = subValue;
      });
      if (filteredChildren.isNotEmpty) {
        candidate.putIfAbsent(parsed.key, () => filteredChildren);
      }
    }
  }
}

/// Holds a parsed enricher fragment.
class _ParsedFragment {
  const _ParsedFragment({
    required this.key,
    required this.value,
    required this.children,
  });

  /// Top-level key from the first line of the fragment.
  final String key;

  /// Top-level scalar value. Empty when the fragment is a nested block.
  final String value;

  /// Indented sub-fields when the fragment is a nested block (e.g. `wind:`).
  final Map<String, String> children;
}

/// Parses an enricher fragment's already-split lines into a [_ParsedFragment].
///
/// Single-line `"key: value"` -> `key='key', value='value', children={}`.
/// Multi-line `"key:\n  sub: val"` -> `key='key', value='', children={sub: val}`.
_ParsedFragment _parseFragment(List<String> lines) {
  final String firstLine = lines.first;
  final int firstColon = firstLine.indexOf(':');
  if (firstColon < 0) {
    return const _ParsedFragment(
      key: '',
      value: '',
      children: <String, String>{},
    );
  }
  final String key = firstLine.substring(0, firstColon).trim();
  final String rawTail = firstLine.substring(firstColon + 1).trim();

  if (lines.length == 1) {
    return _ParsedFragment(
      key: key,
      value: rawTail,
      children: const <String, String>{},
    );
  }

  // Multi-line — every subsequent (indented) line is a sub-field. We strip
  // leading whitespace and parse `subKey: subValue` defensively; lines that
  // do not contain `:` are skipped (defensive: enrichers may emit comments
  // or blank rows in the future).
  final Map<String, String> children = <String, String>{};
  for (final String line in lines.skip(1)) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final int colon = trimmed.indexOf(':');
    if (colon < 0) continue;
    final String subKey = trimmed.substring(0, colon).trim();
    final String subValue = trimmed.substring(colon + 1).trim();
    children[subKey] = subValue;
  }

  return _ParsedFragment(key: key, value: rawTail, children: children);
}

// ---------------------------------------------------------------------------
// Tree-walk helpers — duplicated locally instead of importing private
// helpers from ext_snapshot.dart / ext_find.dart, per the dusk module
// convention (each extension is self-contained; helpers are intentionally
// not exposed across files).
// ---------------------------------------------------------------------------

Map<RenderObject, Element> _buildElementByRenderObject() {
  final Map<RenderObject, Element> index = <RenderObject, Element>{};
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return index;

  void visit(Element element) {
    final RenderObject? renderObject = element.renderObject;
    if (renderObject != null) {
      index.putIfAbsent(renderObject, () => element);
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return index;
}

RenderObject? _renderObjectFor(SemanticsNode node) {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  RenderObject? match;
  void visit(Element element) {
    if (match != null) return;
    final RenderObject? renderObject = element.renderObject;
    if (renderObject != null && identical(renderObject.debugSemantics, node)) {
      match = renderObject;
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return match;
}

Rect _globalRectFor(RenderObject renderObject) {
  if (renderObject is! RenderBox) return Rect.zero;
  if (!renderObject.hasSize) return Rect.zero;
  final Offset topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

/// `true` when the rect has non-zero area AND overlaps the active view
/// logical viewport. Mirrors the actionability-gate's `off-viewport`
/// precondition; here it is informational (the field is emitted; the agent
/// decides) rather than gating.
bool _isVisible(Rect rect) {
  if (rect.width <= 0 || rect.height <= 0) return false;
  final FlutterView? view =
      WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return true;
  final Size viewSize = view.physicalSize / view.devicePixelRatio;
  final Rect viewport = Rect.fromLTWH(0, 0, viewSize.width, viewSize.height);
  return rect.overlaps(viewport);
}

String? _roleFor(SemanticsData data) {
  final SemanticsFlags flags = data.flagsCollection;
  if (flags.isTextField) return 'textbox';
  if (flags.isChecked != CheckedState.none) return 'checkbox';
  if (flags.isLink) return 'link';
  if (flags.isHeader) return 'heading';
  if (flags.isImage) return 'image';
  if (flags.isButton || data.hasAction(SemanticsAction.tap)) {
    return 'button';
  }
  return null;
}

bool _isInteractive(SemanticsData data) {
  if (data.hasAction(SemanticsAction.tap)) return true;
  final SemanticsFlags flags = data.flagsCollection;
  return flags.isTextField ||
      flags.isChecked != CheckedState.none ||
      flags.isLink ||
      flags.isButton ||
      flags.isHeader ||
      flags.isImage;
}

// ---------------------------------------------------------------------------
// Param parsing
// ---------------------------------------------------------------------------

int? _parseInt(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
}

/// Parses the `roles` CSV param into a set of role names. Returns `null`
/// (no filter) when the param is absent or empty. Whitespace around each
/// CSV entry is trimmed; empty entries are dropped.
Set<String>? _parseRoles(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final Set<String> roles = raw
      .split(',')
      .map((String r) => r.trim())
      .where((String r) => r.isNotEmpty)
      .toSet();
  if (roles.isEmpty) return null;
  return roles;
}
