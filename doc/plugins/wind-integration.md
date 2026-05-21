# Wind integration

`WindDuskIntegration` registers a single `DuskSnapshotEnricher`
(`windClassNameEnricher`) that appends Wind-specific styling metadata to
every Dusk snapshot ref whose underlying widget is a W-prefixed widget
(`WDiv`, `WText`, `WButton`, `WInput`, and 13 siblings). The enricher
resolves the widget's `className` through `WindParser` at snapshot time so
the captured values reflect the active breakpoint, brightness, platform,
and pseudo-class states.

## Host integration

Wire `WindDuskIntegration.install()` inside the host's `kDebugMode` branch,
after `DuskPlugin.install()`:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    DuskPlugin.install();
    WindDuskIntegration.install();
  }
  runApp(app);
}
```

`install()` is idempotent; repeat calls are no-ops after the first one
mutates `DuskPlugin.enrichers`. Release builds tree-shake the entire
branch.

## The six core fields

`windClassNameEnricher` emits a `wind:` YAML block under each W-widget
ref. Six core fields are always evaluated; the first four (`breakpoint`,
`brightness`, `platform`, `states`) are always present, the last two
(`bgColor`, `textColor`) appear only when the resolved `WindStyle`
carries a non-null `decoration.color` / `color`.

| Field | Source | Notes |
|:------|:-------|:------|
| `breakpoint` | `WindContext.activeBreakpoint` | One of `xs`, `sm`, `md`, `lg`, `xl`, `2xl`. |
| `brightness` | `WindContext.theme.brightness` | `light` or `dark`. |
| `platform` | `WindContext.platform` | `web`, `ios`, `android`, `macos`, `windows`, `linux`, `fuchsia`. |
| `states` | `WindContext.activeStates` | Pseudo-class states active on the element (e.g. `[hover]`, `[hover, focus]`). |
| `bgColor` | `style.decoration?.color` | 6-char RGB hex (alpha dropped, uppercase). |
| `textColor` | `style.color` | 6-char RGB hex (alpha dropped, uppercase). |

In addition the enricher surfaces ~60 further `WindStyle` fields when they
resolve to non-null / non-identity-default values: layout (`displayType`,
`flexDirection`, `mainAxisAlignment`, ...), sizing (`width`, `height`,
`constraints`, `aspectRatio`), spacing (`padding`, `margin`), typography
(`fontSize`, `fontWeight`, `textAlign`, ...), borders + ring, effects
(`opacity`, `transitionDuration`, `boxShadow`, ...), position, animation,
overflow, SVG, and misc fields. Each value is capped at 60 characters
(truncated with a trailing `…`) so the snapshot stays bounded.

## Example snapshot output

A `WButton` rendered on web at the `md` breakpoint with a hover state
active:

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

The fields appear in deterministic order: the six core fields first
(historical slots 1-6), then layout, sizing, spacing, typography, borders,
effects, position, animation, overflow, SVG, misc, and provenance (opt-in)
groups, in that order.

## Provenance opt-in

For debugging which className prefix activated a given resolved value,
toggle `WindDuskIntegration.enableProvenance(true)` before the next snap.
Subsequent enricher invocations route through `WindParser.parse(...,
trackProvenance: true)` and emit a final `resolvedVia:` line per ref
listing the comma-separated prefix chain per property. Flip the toggle
back to `false` to return to the production-cheap, cache-friendly path.

The provenance toggle is module-static because the `DuskSnapshotEnricher`
typedef is frozen at `String? Function(Element, RefRegistry)`; threading
a third argument through the call would break the contract. See
[enricher-authoring](enricher-authoring) for the frozen contract details.

## Test-only reset

`WindDuskIntegration.resetForTesting()` removes the enricher from
`DuskPlugin.enrichers`, clears the `_installed` flag, and resets the
provenance toggle to `false`. Production code never calls this.
