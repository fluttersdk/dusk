import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../ref_registry.dart';

/// Structured error envelope appended to every Dusk action-handler error
/// response.
///
/// The wire shape of `ServiceExtensionResponse.error(...)` historically
/// carried a free-form string (e.g. `"Widget ref=e1 is not actionable: not
/// enabled"`). Agents and tests grep this string for substrings like
/// `"not enabled"`, `"zero rect"`, `"off-viewport"`. That contract is
/// preserved.
///
/// In addition, this Step 3.3 envelope ships alongside the message inside a
/// JSON wrapper produced by [wrapErrorDetail]:
///
/// ```json
/// {
///   "message": "Widget ref=e1 is not actionable: not enabled",
///   "envelope": {"type": "disabled", "widget_path": "e1", "suggestions": []}
/// }
/// ```
///
/// The wrapper IS a string from the VM Service's perspective, so legacy
/// callers doing `response.errorDetail.contains("not enabled")` continue to
/// match (the substring sits verbatim inside the JSON `message` field).
/// New callers parse the string as JSON to read the structured envelope.
class DuskErrorEnvelope {
  /// Creates a [DuskErrorEnvelope].
  ///
  /// [type] is the machine-readable failure category; see class-level docs
  /// for the closed set. [widgetPath] is the `eN` / `qN` token or any other
  /// identifier the agent can carry forward. [suggestions] is the (possibly
  /// empty) list of fuzzy-matched alternative refs / texts for `not_found`
  /// failures; empty for every other type.
  const DuskErrorEnvelope({
    required this.type,
    required this.widgetPath,
    required this.suggestions,
  });

  /// Machine-readable failure category. One of: `'timeout'`, `'not_found'`,
  /// `'obscured'`, `'disabled'`, `'stale'`, `'zero_rect'`, `'off_viewport'`,
  /// `'not_stable'`, `'missing_param'`, `'unexpected'`.
  final String type;

  /// Token / path the failure points at (e.g. `e7`, `q3`), or `null` when
  /// the failure is not bound to a specific ref (e.g. missing param).
  final String? widgetPath;

  /// Top-N (default 3) fuzzy-matched alternative refs / texts for
  /// `not_found` failures, sorted by ascending Levenshtein distance.
  /// Empty list for any other type.
  final List<String> suggestions;

  /// Serialises to the wire shape consumed by the MCP layer.
  ///
  /// `widget_path` is OMITTED (rather than emitted as `null`) when no
  /// widget context is available. `suggestions` is always present, even
  /// when empty, so callers do not need a null-check.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'type': type,
      'suggestions': suggestions,
    };
    if (widgetPath != null) {
      json['widget_path'] = widgetPath;
    }
    return json;
  }

  // ---------------------------------------------------------------------------
  // Factories
  // ---------------------------------------------------------------------------

  /// Envelope for a missing-ref / unknown-ref failure (type `not_found`).
  ///
  /// [candidates] is the iterable of strings the agent might have meant
  /// (currently a snapshot of active refs + semantic labels gathered by
  /// [collectSnapshotCandidates]). The top 3 closest by Levenshtein
  /// distance (cap 3) are surfaced in [suggestions].
  factory DuskErrorEnvelope.notFound({
    required String ref,
    Iterable<String> candidates = const <String>[],
  }) =>
      DuskErrorEnvelope(
        type: 'not_found',
        widgetPath: ref,
        suggestions: fuzzyMatch(ref, candidates),
      );

  /// Envelope for a `DuskActionabilityException` failure. [reason] is the
  /// raw substring from the exception (`"not enabled"`, `"zero rect"`,
  /// etc.); unknown reasons land under `'unexpected'` so the agent can
  /// still branch on `type`.
  factory DuskErrorEnvelope.fromActionabilityReason(
    String ref,
    String reason,
  ) {
    final String type;
    if (reason.contains('not enabled')) {
      type = 'disabled';
    } else if (reason.contains('zero rect')) {
      type = 'zero_rect';
    } else if (reason.contains('off-viewport')) {
      type = 'off_viewport';
    } else if (reason.contains('not stable')) {
      type = 'not_stable';
    } else if (reason.contains('obscured by')) {
      type = 'obscured';
    } else {
      type = 'unexpected';
    }
    return DuskErrorEnvelope(
      type: type,
      widgetPath: ref,
      suggestions: const <String>[],
    );
  }

  /// Envelope for a `DuskStaleHandleException`: the `qN` handle's stored
  /// predicates no longer match anything in the live tree.
  factory DuskErrorEnvelope.stale(String ref) => DuskErrorEnvelope(
        type: 'stale',
        widgetPath: ref,
        suggestions: const <String>[],
      );

  /// Envelope for a missing required parameter. [paramName] is included
  /// purely for documentation; the [type] field is what agents branch on.
  factory DuskErrorEnvelope.missingParam(String paramName) =>
      const DuskErrorEnvelope(
        type: 'missing_param',
        widgetPath: null,
        suggestions: <String>[],
      );

  /// Envelope for a wait/find timeout. [widgetPath] is optional — wait_for
  /// queries by text rather than by ref.
  factory DuskErrorEnvelope.timeout({String? widgetPath}) => DuskErrorEnvelope(
        type: 'timeout',
        widgetPath: widgetPath,
        suggestions: const <String>[],
      );

  /// Envelope for any failure that does not fit a typed bucket — handler
  /// catch-blocks that fall through to `e.toString()`.
  factory DuskErrorEnvelope.unexpected({String? widgetPath}) =>
      DuskErrorEnvelope(
        type: 'unexpected',
        widgetPath: widgetPath,
        suggestions: const <String>[],
      );
}

// ---------------------------------------------------------------------------
// Wire wrapper
// ---------------------------------------------------------------------------

/// Wraps a legacy free-form [message] together with a structured [envelope]
/// inside a single JSON string suitable for use as the `errorDetail` payload
/// of a [developer.ServiceExtensionResponse.error] response.
///
/// Wire shape:
///
/// ```json
/// {"message":"<message>","envelope":{"type":"...", ...}}
/// ```
///
/// Substring back-compat: every byte of [message] sits verbatim inside the
/// JSON `message` field, so legacy callers that do
/// `response.errorDetail.contains("not enabled")` continue to match. Note
/// that JSON encoding escapes interior quotes to `\"`; tests that match
/// substrings carrying a literal `"` should match against the JSON-encoded
/// form (e.g. `contains(r'missing required param \"ref\"')`) or use
/// [parseEnvelopeFromErrorDetail] / [parseMessageFromErrorDetail].
///
/// Structured access: new callers decode the string as JSON and read
/// `decoded['envelope']` for the [DuskErrorEnvelope.toJson] payload, or
/// `decoded['message']` for the original free-form message.
String wrapErrorDetail(String message, DuskErrorEnvelope envelope) {
  return jsonEncode(<String, dynamic>{
    'message': message,
    'envelope': envelope.toJson(),
  });
}

/// Parses the envelope JSON out of an [errorDetail] string produced by
/// [wrapErrorDetail].
///
/// Returns `null` when [errorDetail] is not a JSON object carrying an
/// `envelope` key (e.g. a pre-Step-3.3 plain string or a non-envelope JSON
/// payload). Safe to call on any error-detail string.
Map<String, dynamic>? parseEnvelopeFromErrorDetail(String errorDetail) {
  try {
    final dynamic decoded = jsonDecode(errorDetail);
    if (decoded is Map<String, dynamic>) {
      final dynamic envelope = decoded['envelope'];
      if (envelope is Map<String, dynamic>) return envelope;
    }
  } catch (_) {
    // Not JSON — legacy plain string.
  }
  return null;
}

/// Parses the original free-form message out of an [errorDetail] string
/// produced by [wrapErrorDetail].
///
/// Returns the input verbatim when the string is not a JSON envelope (a
/// pre-Step-3.3 plain string survives untouched). New callers that want
/// JSON-escape-free access to the original message use this helper instead
/// of substring-matching the wire string.
String parseMessageFromErrorDetail(String errorDetail) {
  try {
    final dynamic decoded = jsonDecode(errorDetail);
    if (decoded is Map<String, dynamic>) {
      final dynamic message = decoded['message'];
      if (message is String) return message;
    }
  } catch (_) {
    // Not JSON — legacy plain string; return as-is.
  }
  return errorDetail;
}

// ---------------------------------------------------------------------------
// Fuzzy match — Levenshtein-based, no external deps
// ---------------------------------------------------------------------------

/// Computes the Levenshtein edit distance between [a] and [b].
///
/// Simple `O(|a| * |b|)` DP implementation using two rolling rows. No
/// external dependencies. Used by [fuzzyMatch] to score `not_found`
/// suggestions; intentionally not exposed for general string-similarity
/// duty (the MUST NOT clause bans complex string-similarity libs).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final int m = a.length;
  final int n = b.length;
  List<int> prev = List<int>.generate(n + 1, (int i) => i);
  List<int> curr = List<int>.filled(n + 1, 0);

  for (int i = 1; i <= m; i++) {
    curr[0] = i;
    for (int j = 1; j <= n; j++) {
      final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    final List<int> tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[n];
}

/// Returns the top [topN] candidates from [candidates] whose effective
/// distance to [query] is `<= maxDistance`, sorted ascending by distance.
///
/// "Effective distance" is the minimum of:
///
/// * the raw Levenshtein edit distance (typos / substitutions), and
/// * `1` when [query] is a non-empty prefix of the candidate (the
///   candidate is the query plus a tail — "Submi" is a prefix of
///   "Submit", "Submitted", "Submission"; agents typing a partial label
///   get the full completions surfaced).
///
/// The prefix bonus is what makes the briefing's worked example
/// (`Submi → [Submit, Submitted, Submission]`) work: raw Levenshtein
/// scores "Submi"/"Submission" at 5, far above any reasonable typo
/// threshold, even though the agent's intent is obvious.
///
/// Deduplicates: an exact-match candidate appearing twice contributes one
/// suggestion. An empty [query] returns an empty list — there is no
/// meaningful "closest" to nothing.
///
/// The default `maxDistance: 3` mirrors Playwright's "did you mean?" UX
/// for typos; the prefix bonus extends that to partial-label completion.
List<String> fuzzyMatch(
  String query,
  Iterable<String> candidates, {
  int maxDistance = 3,
  int topN = 3,
}) {
  if (query.isEmpty) return const <String>[];

  // 1. Compute distance for every candidate, filter to threshold, dedupe.
  //    Prefix-of-candidate gets distance 1 (one logical "completion"
  //    operation) so partial-label typing still surfaces matches that a
  //    raw Levenshtein bound of 3 would otherwise reject.
  final Map<String, int> seen = <String, int>{};
  for (final String candidate in candidates) {
    if (candidate.isEmpty) continue;
    if (seen.containsKey(candidate)) continue;
    final int raw = levenshtein(query, candidate);
    final int distance = candidate.startsWith(query) ? math.min(raw, 1) : raw;
    if (distance <= maxDistance) {
      seen[candidate] = distance;
    }
  }

  // 2. Sort ascending by distance — stable enough; ties break by insertion
  //    order via Dart's stable sort.
  final List<MapEntry<String, int>> sorted = seen.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
        a.value.compareTo(b.value));

  // 3. Take top N.
  return sorted
      .take(topN)
      .map((MapEntry<String, int> e) => e.key)
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// Live-tree candidate collection
// ---------------------------------------------------------------------------

/// Gathers candidate strings from the current Dusk runtime state to feed
/// [DuskErrorEnvelope.notFound]'s fuzzy match.
///
/// Three sources, in this order:
///
/// 1. Every active `eN` token currently registered in [RefRegistry] — so a
///    typo like `e10` lists `e1, e11, e12` as suggestions.
/// 2. Every `qN` token currently registered in [RefRegistry].
/// 3. Every semantic label reachable from the active pipeline owners.
///
/// Returns up to [limit] strings to keep the Levenshtein computation bounded
/// (default 50; the snapshot rarely contains more interactive labels). Order
/// is irrelevant — [fuzzyMatch] sorts by distance.
///
/// Best-effort: when the widget tree is detached (headless / between-tests)
/// the result is the union of whatever is available, possibly empty.
List<String> collectSnapshotCandidates({int limit = 50}) {
  final List<String> out = <String>[];

  // 1. Active refs from RefRegistry. Includes both e* and q* tokens.
  for (final String token in RefRegistry.activeRefs()) {
    if (out.length >= limit) return out;
    out.add(token);
  }

  // 2. Walk the live Semantics tree for labels. We walk through every
  //    pipeline owner because the Flutter test harness mounts the widget
  //    tree under a CHILD pipeline owner (mirrors ext_find.dart's walk).
  try {
    void visit(SemanticsNode node) {
      if (out.length >= limit) return;
      if (node.label.isNotEmpty) {
        out.add(node.label);
      }
      node.visitChildren((SemanticsNode child) {
        visit(child);
        return out.length < limit;
      });
    }

    void visitOwner(PipelineOwner owner) {
      if (out.length >= limit) return;
      final SemanticsNode? root = owner.semanticsOwner?.rootSemanticsNode;
      if (root != null) visit(root);
      owner.visitChildren((PipelineOwner child) {
        if (out.length < limit) visitOwner(child);
      });
    }

    visitOwner(RendererBinding.instance.rootPipelineOwner);
  } catch (_) {
    // Headless test contexts may not have a binding initialised; swallow.
  }

  return out;
}
