# Magic integration

`MagicDuskIntegration` is the glue layer between the `magic` Flutter framework
(Laravel-inspired primitives like `MagicForm`, `MagicRouter`, `Gate`, `Auth`,
`Echo`) and the `fluttersdk_dusk` snapshot pipeline. It registers a fixed set
of `DuskSnapshotEnricher` callbacks against `DuskPlugin.enrichers`, so every
`dusk:snap` (or `dusk_snap` MCP) output carries Magic-aware annotations
alongside the standard Semantics tree.

This document covers the five behavioural enrichers most likely to drive an
agent's reasoning loop. The full integration ships fourteen enrichers; the
nine not covered here (`magicFormEnricher`, `magicNavigationEnricher`,
`magicControllerFlagsEnricher`, `magicRouteParamsEnricher`,
`magicEchoConnectionEnricher`, `magicGateResultsAllEnricher`,
`magicRecentHttpEnricher`, `magicRecentLogsEnricher`,
`magicRecentExceptionsEnricher`) surface form fields, the active route,
controller flags, route parameters, broadcast connection state, recent
gate results, and the telescope HTTP / log / exception ring buffers; read
the dartdoc on `MagicDuskIntegration` for those.

## When to call install

`MagicDuskIntegration.install()` must run **after** `Magic.init()` has
booted the container (the enrichers read from `Magic.controllers`,
`MagicRouter.instance`, `Gate.manager`, and `Auth.user()`, all of which
require the service providers to be live). It must also run **after**
`DuskPlugin.install()`, because the `DuskPlugin.enrichers` list is the
target the integration mutates.

The canonical debug-only host integration:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init();
  if (kDebugMode) {
    DuskPlugin.install();
    MagicDuskIntegration.install();
  }
  runApp(MagicApplication());
}
```

`install()` is idempotent; calling it twice in the same isolate is a no-op
after the first call, matching `DuskPlugin.install()` semantics. Release
builds tree-shake the entire `kDebugMode` branch.

## The five core enrichers

### magicControllerEnricher

Emits `magicControllerState: <ControllerClass>.<rxStatus>` for the first
`MagicStateMixin`-bearing controller registered via `Magic.put`. The status
is the enum name of the controller's `rxStatus.type` (`success`, `loading`,
`error`, or `empty`). Returns null when no `MagicStateMixin` controller is
registered, so a guest-only or pre-controller view collapses cleanly.

### magicFormErrorsEnricher

Emits `magicFormErrors: <field>="<text>",...` for elements under a
`MagicForm` whose controller carries server-side `ValidatesRequests` errors
that match the form's own field set. Cross-form leak is guarded by
intersecting the controller's `validationErrors.keys` with the form's
`fieldNames`; messages longer than 80 characters are truncated to a
77-character prefix followed by `...`. Returns null when the controller
has no errors, no `ValidatesRequests` mixin, or no errors matching the
form's fields.

### magicGateResultEnricher

Emits `magicGateResult: <ability>.<allowed|denied>` for the most recently
cached `GateResult` in `Gate.manager`. The cache is populated transparently
by every `Gate.allows` / `Gate.denies` call, so an agent reading the
snapshot can confirm which authorization check ran last and what it
returned. Returns null when no check has run since the last
`Gate.manager.flush()`.

### magicMiddlewareEnricher

Emits `magicMiddleware: <name1,name2>` for the active route's resolved
middlewares. Reads `MagicRouter.instance.currentRoute.middlewares` and
labels each entry by class `toString()` for `MagicMiddleware` instances or
by the raw string for kernel-aliased middlewares. Returns null when no
route is active or the route has zero middlewares.

### magicAuthUserEnricher

Emits `magicAuthUser: <id>[:<displayName>]` for the authenticated user
surfaced by `Auth.user()`. Falls back to `magicAuthUser: <id>` (no trailing
colon) when `display_name` is null, missing, or empty. Returns null when
the session is a guest.

## Example snapshot output

A typical snapshot fragment for a `MonitorListView` rendered inside a
`MagicForm` with one validation error and a recently checked `monitors.view`
ability:

```yaml
- ref: e3
  role: button
  label: "Create Monitor"
  bounds: 16,128,160,40
  magicRoute: /monitors
  magicControllerState: MonitorController.success
  magicGateResult: monitors.create.allowed
  magicMiddleware: EnsureAuthenticated,VerifyTeamMembership
  magicAuthUser: 4f9a-2b1c:Anilcan Cakir
- ref: e4
  role: textField
  label: "Name"
  bounds: 16,200,328,48
  magicFormField: name
  magicFormErrors: name="The name field is required."
```

The five core enrichers populate the lines under each ref in the order
they were registered. The dispatcher iterates `DuskPlugin.enrichers` in
insertion order and concatenates non-null returns; if two enrichers ever
emit the same key, the **first** insertion wins (per the
`DuskSnapshotEnricher` first-write-wins contract).

## Test-only reset

`MagicDuskIntegration.resetForTesting()` removes every enricher from
`DuskPlugin.enrichers`, cancels the internal Echo connection-state
subscription, and clears the idempotency guard. Pair it with
`DuskPlugin`'s reset hook in `tearDown` so consecutive widget tests start
with a clean enricher chain.

## Frozen contract

Every Magic enricher honours the `DuskSnapshotEnricher` typedef contract:
synchronous, stateless, never retains the `Element` across calls, returns
null when the element is not relevant. The contract is frozen for the
alpha-2 cycle; see [enricher-authoring](enricher-authoring) for the full
typedef and authoring guide.
