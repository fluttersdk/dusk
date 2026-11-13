# Magic integration

`MagicTapirIntegration` is the glue layer that registers Magic-aware snapshot enrichers with `tapir`.

It sits between the `magic` Flutter framework (Laravel-inspired primitives like `MagicForm`,
`MagicRouter`, `Gate`, `Auth`, `Echo`) and the `tapir` snapshot pipeline. It registers a fixed
set of `TapirSnapshotEnricher` callbacks against `TapirPlugin.enrichers`, so a `tapir:snap`
(or `tapir_snap` MCP) taken with `includeEnrichers` carries Magic-aware annotations
alongside the standard Semantics tree.

`MagicTapirIntegration` ships in the **`magic_devtools`** package, not in magic
core. Add it as a dev_dependency (it is debug-only; release builds tree-shake
the `!kReleaseMode` branch that calls `install()`):

```yaml
dev_dependencies:
  magic_devtools: ^<version>
```

This document covers the behavioural enrichers most likely to drive an
agent's reasoning loop. The others (`magicFormEnricher`, `magicNavigationEnricher`,
`magicControllerFlagsEnricher`, `magicRouteParamsEnricher`,
`magicEchoConnectionEnricher`, `magicGateResultsAllEnricher`,
`magicRecentHttpEnricher`, `magicRecentLogsEnricher`,
`magicRecentExceptionsEnricher`) surface form fields, the active route,
controller flags, route parameters, broadcast connection state, recent
gate results, and the crumbs HTTP / log / exception ring buffers; read
the dartdoc on `MagicTapirIntegration` for those.

- [When to call install](#when-to-call-install)
- [The core enrichers](#the-core-enrichers)
- [Example snapshot output](#example-snapshot-output)
- [Test-only reset](#test-only-reset)
- [Frozen contract](#frozen-contract)
- [Related Documentation](#related-documentation)

<a name="when-to-call-install"></a>
## When to call install

`MagicTapirIntegration.install()` must run **after** `Magic.init()` has
booted the container (the enrichers read from `Magic.controllers`,
`MagicRouter.instance`, `Gate.manager`, and `Auth.user()`, all of which
require the service providers to be live). It must also run **after**
`TapirPlugin.install()`, because the `TapirPlugin.enrichers` list is the
target the integration mutates.

The canonical debug-only host integration (`MagicTapirIntegration` comes from
the `magic_devtools` dev_dependency):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_devtools/tapir.dart'; // from the magic_devtools dev_dependency
import 'package:tapir/tapir.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) TapirPlugin.install();
  await Magic.init();
  if (!kReleaseMode) MagicTapirIntegration.install();
  runApp(const MagicApplication());
}
```

`install()` is idempotent; calling it twice in the same isolate is a no-op
after the first call, matching `TapirPlugin.install()` semantics. Release
builds tree-shake both `!kReleaseMode` branches. Installing tapir before `Magic.init()` keeps
the driver live while Magic boots.

<a name="the-core-enrichers"></a>
## The core enrichers

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

<a name="example-snapshot-output"></a>
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

The enrichers populate the lines under each ref in the order
they were registered. The dispatcher iterates `TapirPlugin.enrichers` in
insertion order and writes every non-null fragment under the ref. Nothing
deduplicates keys: if two enrichers emit the same key, the snapshot carries
both lines, so keep enricher keys distinct.

<a name="test-only-reset"></a>
## Test-only reset

`MagicTapirIntegration.resetForTesting()` removes every enricher from
`TapirPlugin.enrichers`, cancels the internal Echo connection-state
subscription, and clears the idempotency guard. Call it in `tearDown` so
consecutive widget tests start with a clean enricher chain.

<a name="frozen-contract"></a>
## Frozen contract

Every Magic enricher honours the `TapirSnapshotEnricher` typedef contract:
synchronous, stateless, never retains the `Element` across calls, returns
null when the element is not relevant. The typedef is frozen; see
[enricher-authoring.md](enricher-authoring.md) for the full typedef and authoring guide.

<a name="related-documentation"></a>
## Related Documentation

- [enricher-authoring.md](enricher-authoring.md): the typedef, the four-clause contract and how to write your own enricher.
- [wind-integration.md](wind-integration.md): the `wind:` block that tapir emits ahead of these enrichers.
