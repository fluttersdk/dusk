---
paths:
  - "lib/src/extensions/**"
  - "lib/src/ref_registry.dart"
  - "lib/src/utils/actionability_gate.dart"
  - "lib/src/utils/dusk_exceptions.dart"
  - "lib/src/utils/error_envelope.dart"
  - "test/src/extensions/**"
---

# Extensions Subsystem

## Registration

Every VM Service extension is registered inside a `registerXExtensions()` (or `registerXExtension()` for single-extension files) function exported from the matching `ext_<name>.dart` file. The aggregator at `lib/src/extensions/register_dusk_extensions.dart` calls all 16 registration functions; `DuskPlugin.install()` calls the aggregator exactly once.

Use `registerExtensionIdempotent` from `fluttersdk_artisan` for every `developer.registerExtension` call:

```dart
registerExtensionIdempotent('ext.dusk.<verb>', _handler);
```

Direct `developer.registerExtension` throws `ArgumentError: Extension already registered` on the second call within an isolate lifetime; idempotent registration silently no-ops the second call. Hot-restart spawns a new isolate so the registration table is fresh; the guard exists for double-`install()` paths only.

Naming follows `ext.dusk.<verb_or_noun>` snake_case, terminal segment only. Prefix is enforced by the Dart VM at registration time; misuse throws `ArgumentError`.

## Handler signature

```dart
Future<ServiceExtensionResponse> _handler(String method, Map<String, String> params) async {
  // 1. Parse params. All values arrive as strings; integers via int.tryParse.
  final ref = params['ref'] ?? '';
  final timeout = int.tryParse(params['timeout'] ?? '') ?? 5000;

  // 2. Validate. Return ServiceExtensionResponse.error on bad input.
  if (ref.isEmpty) {
    return ServiceExtensionResponse.error(
      ServiceExtensionResponse.invalidParams,
      jsonEncode({'message': 'ref is required', 'method': method}),
    );
  }

  // 3. Run action.
  // 4. Return result.
  return ServiceExtensionResponse.result(jsonEncode({'ok': true}));
}
```

Errors use `ServiceExtensionResponse.extensionError` (`-32000`) for runtime failures, `invalidParams` (`-32602`) for bad input. The `errorDetail` payload is JSON-encoded with at minimum a `message` key; include `method` and any structured context (`reason`, `widgetPath`, `suggestions`) consumed by `DuskErrorEnvelope.fromActionabilityReason` in `lib/src/utils/error_envelope.dart`.

## Actionability gate

Seven pointer handlers (`tap`, `hover`, `drag`, `dblclick`, `right_click`, `triple_click`) and one text handler (`type`) route every action through `ensureActionable(ref, {checkStable, checkReceivesEvents})` from `lib/src/utils/actionability_gate.dart`. The gate runs six checks in this exact order; new checks append, never reorder (agents parse the reason substring):

| Step | Check | Failure reason substring | Opt-out |
|---|---|---|---|
| 0 | `element.findRenderObject()` returns non-null and is mounted | `"defunct (element no longer mounted)"` | none |
| 1 | `node.flagsCollection.isEnabled != Tristate.isFalse` | `"not enabled"` | none |
| 2 | `rect.width > 0 && rect.height > 0` | `"zero rect"` | none |
| 3 | rect overlaps viewport (auto-`showOnScreen` first when a `Scrollable` ancestor exists) | `"off-viewport (rect=..., viewport=...)"` | none |
| 4 | 2-frame rect drift `<= 0.5px` | `"not stable (rect changed by Xpx)"` | `--no-checkStable` |
| 5 | hit-test path at `rect.center` includes the target render object or a descendant | `"obscured by other widget (top=...)"` | `--no-checkReceivesEvents` |

Failures throw `DuskActionabilityException(ref, reason)` from `lib/src/utils/dusk_exceptions.dart`; catch it inside the handler and return `ServiceExtensionResponse.error(extensionError, jsonEncode(DuskErrorEnvelope.fromActionabilityReason(ref, reason).toJson()))`. The flat message `"Widget ref=$ref is not actionable: $reason"` is the user-facing field; the `reason` substring is the agent-branch field.

Three handlers intentionally skip the gate: `scroll` operates on the parent scrollable not the ref target, `select_option` dispatches through Material/Cupertino popup machinery that owns its own enabled check, `press_key` targets the focused widget rather than a ref.

## RefRegistry usage

Snapshot extensions (`ext_snapshot.dart`, `ext_observe.dart`) mint `e<N>` tokens via `RefRegistry.register(rect, element, groupId, isTextField, [node, renderObject])`. The registry dedupes by `SemanticsNode.id`; the same widget across snapshots returns the same `e<N>` and refreshes the entry's `groupId` to the latest snapshot id.

Query extensions (`ext_find.dart`, `ext_observe.dart`) mint fresh `q<N>` tokens via `RefRegistry.registerQuery(DuskQuery(text: ..., semanticsLabel: ..., keyValue: ...))`. Query tokens never dedupe and survive snapshot-group disposal; they re-walk the live Semantics tree on every action call.

Action handlers resolve via `resolveRefForAction(ref)` in `lib/src/extensions/ext_pointer.dart`. Prefix `q` looks up the predicate and re-walks; any other prefix routes through `RefRegistry.lookup`. Stale `q<N>` handles throw `DuskStaleHandleException`; agents recover by calling `dusk_find` again. The `e<N>` and `q<N>` token spaces are disjoint, never mint across them.

## Snapshot enricher contract (FROZEN)

`DuskSnapshotEnricher` in `lib/src/dusk_snapshot_enricher.dart:23` is `String? Function(Element element, RefRegistry refs)`. Implementations return a YAML fragment (indented under the snapshot node) or `null` to skip. Magic ships 7 enrichers (form fields, route, auth user, recent HTTP, etc.) via `MagicDuskIntegration`.

Wind diagnostics flow through `fluttersdk_wind_diagnostics_contracts.WindDebugRegistry.current?.resolve(element)` inside `ext_snapshot.dart:204` and `ext_observe.dart:317` ahead of the enricher loop. This is a neutral bridge package; do not import `fluttersdk_wind` from this package.

Element references inside an enricher are never retained across calls; the contract is synchronous and stateless.

## Adding a new extension

1. Add the handler to a relevant `ext_<group>.dart` file (or create a new file). Wire it into `registerXExtensions()`.
2. Add the file's registration call to `register_dusk_extensions.dart:registerAllDuskExtensions()`.
3. Add a matching `ArtisanCommand` under `lib/src/commands/dusk_<verb>_command.dart` (see `.claude/rules/commands.md`).
4. Add the command to `DuskArtisanProvider.commands()` and a const `McpToolDescriptor` to `mcpTools()`.
5. Add a unit test under `test/src/extensions/ext_<group>_test.dart`.
6. Update docs per `.claude/rules/docs.md`: README features table, ARCHITECTURE.md VM Service surface, CHANGELOG `[Unreleased] Added`, `doc/commands/dusk-<verb>.md`, `doc/mcp/tool-reference.md`, `llms.txt` Commands section.
