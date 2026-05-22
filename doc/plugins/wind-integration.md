# Wind integration

Wind 1.0.0-alpha.10 removed `WindDuskIntegration` and all dusk-specific shim code from the wind package.
Wind state now surfaces through the neutral `fluttersdk_wind_diagnostics_contracts.WindDebugRegistry` bridge,
which both wind (prod dep) and dusk (prod dep) depend on directly without either depending on the other.
Dusk reads `WindDebugRegistry.current?.resolve(element)` inside `ext_snapshot.dart` and `ext_observe.dart`
ahead of the enricher loop, so no dusk-side install call is required for wind metadata to appear.
The 6 core fields still appear under the `wind:` block of every W-prefixed widget's snapshot ref.

## Host integration

Call `Wind.installDebugResolver()` inside the host's `kDebugMode` branch, after `DuskPlugin.install()`.
No additional dusk-side registration is required; dusk reads the resolver through the neutral contracts bridge
at snap time.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    DuskPlugin.install();
    Wind.installDebugResolver();
  }
  runApp(app);
}
```

Both calls are idempotent. Release builds tree-shake the entire `kDebugMode` branch on dart2js (web) and
dart2native (mobile and desktop AOT).

## The six core fields

Dusk emits a `wind:` YAML block under each W-widget ref by resolving the element through
`WindDebugRegistry.current?.resolve(element)` before the enricher loop runs. Six core fields are always
evaluated. The first four (`breakpoint`, `brightness`, `platform`, `states`) are always present; the last two
(`bgColor`, `textColor`) appear only when the resolved `WindStyle` carries a non-null `decoration.color` /
`color`.

| Field | Source | Notes |
|:------|:-------|:------|
| `breakpoint` | `WindContext.activeBreakpoint` | One of `xs`, `sm`, `md`, `lg`, `xl`, `2xl`. |
| `brightness` | `WindContext.theme.brightness` | `light` or `dark`. |
| `platform` | `WindContext.platform` | `web`, `ios`, `android`, `macos`, `windows`, `linux`, `fuchsia`. |
| `states` | `WindContext.activeStates` | Pseudo-class states active on the element (e.g. `[hover]`, `[hover, focus]`). |
| `bgColor` | `style.decoration?.color` | 6-char RGB hex (alpha dropped, uppercase). |
| `textColor` | `style.color` | 6-char RGB hex (alpha dropped, uppercase). |

## Example snapshot output

A `WButton` rendered on web at the `md` breakpoint with a hover state active:

```yaml
- ref: e7
  role: button
  label: "Sign In"
  bounds: 240,360,160,40
  wind:
    breakpoint: md
    brightness: light
    platform: web
    states: [hover]
    bgColor: '#3B82F6'
    textColor: '#FFFFFF'
    displayType: flex
    mainAxisAlignment: center
    crossAxisAlignment: center
    padding: 12,16,12,16
    fontSize: 14
    fontWeight: 600
```

## Provenance opt-in

<!-- TODO: confirm provenance API in wind 1.0.0-alpha.10+ -->

The provenance toggle now lives on the wind-side API. Pass `trackProvenance: true` to
`Wind.installDebugResolver()` (or equivalent per the wind 1.0.0-alpha.10 API) to enable prefix-chain
tracking. When enabled, a `resolvedVia:` line appears per ref listing the comma-separated prefix chain per
property, showing which `className` prefix activated each resolved value. Disable provenance to return to the
production-cheap, cache-friendly path.

The `DuskSnapshotEnricher` typedef is frozen at `String? Function(Element, RefRegistry)`; threading a third
argument through the call would break the contract. See [enricher-authoring](enricher-authoring) for the
frozen contract details.

## Test-only reset

<!-- TODO: confirm exact reset API in wind 1.0.0-alpha.10+ -->

The per-test reset helper was removed along with the integration class in wind 1.0.0-alpha.10.
Tests that previously relied on it should reset via `WindDebugRegistry.resetForTesting()` on the contracts
bridge instead. Production code never calls any reset method.

## Cross-package coupling

The `fluttersdk_wind_diagnostics_contracts` package is a hosted dependency for both `fluttersdk_dusk` and
`wind`; the outer `pubspec.yaml` may need a `dependency_overrides` block pointing to the local path during
local development until the upstream repository is published on pub.dev (see CLAUDE.local.md wind alpha-10
migration section for the exact override snippet).
