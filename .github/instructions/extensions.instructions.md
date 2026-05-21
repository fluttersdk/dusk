---
paths: lib/src/extensions/**, test/src/extensions/**
---

# VM Service Extensions: Rules

## Registration

- Every handler registers via `registerExtensionIdempotent` (imported from `fluttersdk_artisan`). Direct calls to `developer.registerExtension` are forbidden; duplicate registration on hot-restart throws `ArgumentError` without the idempotent guard.
- All registrations are aggregated through `registerDuskExtensions()` in `lib/src/extensions/` so the install entry point stays a single call.

## Handler signature

Every VM Service handler must match this exact signature:

```dart
Future<ServiceExtensionResponse> Function(String method, Map<String, String> params)
```

- Parse integer params via `int.tryParse(params['key'] ?? '')`. Never assume a param is present.
- Success response: `ServiceExtensionResponse.result(jsonEncode(payload))`.
- Error response: `ServiceExtensionResponse.error(ServiceExtensionResponse.extensionError, msg)`.

## Actionability gate (5-gate)

- `tap`, `hover`, `drag`, and `type` handlers MUST route through `ensureActionable` from `utils/actionability_gate.dart` before synthesising any pointer or key event.
- `scroll`, `select_option`, and `press_key` intentionally skip the gate: scroll targets the parent scrollable, select_option relies on Material/Cupertino popup machinery, press_key targets the focused widget.
- Gate preconditions are evaluated in fixed order (Wave 3 expanded the alpha-1 3-gate to the current 5-gate per `lib/src/utils/actionability_gate.dart`): (1) enabled, (2) zero-area rect, (3) off-viewport, (4) stable (rect unchanged across 2 frames), (5) receives-events (hit-test confirms ref is the front-most pointer target). Do NOT reorder; agents parse the exception message substring for branching.
- Opt-out flags: `checkStable=false` and `checkReceivesEvents=false` (both default `true`) disable the Wave 3 additions when a caller needs the alpha-1 baseline.

## Actionability exception shape (FROZEN)

The exception message format is a load-bearing contract:

```
"Widget ref=$ref is not actionable: $reason"
```

Where `$reason` is exactly one of: `"not enabled"`, `"zero rect"`, `"off-viewport (rect=..., viewport=...)"`, `"not stable"`, `"obscured by ..."`.

Do NOT alter this format in any alpha-2 patch. Agents branch by substring-matching `$reason` against this 5-entry set.

## Ref tokens

- `e<N>` tokens are minted at snap time (frozen to the snapshot). Use only in `dusk_snap`.
- `q<N>` tokens are minted by `dusk_find` (re-resolvable on every action call). Use only in `dusk_find`.
- Never mix the two token spaces inside a single handler implementation.
