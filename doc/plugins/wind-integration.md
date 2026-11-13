# Wind integration

Tapir reads the state of `wind_kit` widgets through a neutral diagnostics bridge, so a host only calls `Wind.installDebugResolver()`.

`wind_kit` publishes runtime diagnostics through `wind_kit_diagnostics_contracts.WindDebugRegistry`,
a package both `wind_kit` and `tapir` depend on without depending on each other. Tapir reads
`WindDebugRegistry.current?.resolve(element)` inside `ext_snapshot.dart` and `ext_observe.dart`
ahead of the enricher loop, so no tapir-side install call is required for wind metadata to
appear. The `wind:` block shows under the ref of every W-prefixed widget that has a `className`,
in a snapshot taken with `includeEnrichers` on (`tapir:snap --includeEnrichers`, or the
`includeEnrichers` flag of `tapir_snap` and `tapir_observe`). `tapir_observe` projects the block:
its default and `"true"` modes return only `breakpoint` and `states`, and `className`, `brightness`,
`platform` and the colours need `includeEnrichers: "full"`.

- [Host integration](#host-integration)
- [The core fields](#the-core-fields)
- [Example snapshot output](#example-snapshot-output)
- [Test-only reset](#test-only-reset)
- [Cross-package coupling](#cross-package-coupling)
- [Related Documentation](#related-documentation)

<a name="host-integration"></a>
## Host integration

Call `Wind.installDebugResolver()` (exported by `package:wind_kit/wind_kit.dart`) inside the host's
`!kReleaseMode` branch, after `TapirPlugin.install()`. No additional tapir-side registration is
required; tapir reads the resolver through the neutral contracts bridge at snap time.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tapir/tapir.dart';
import 'package:wind_kit/wind_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    TapirPlugin.install();
    Wind.installDebugResolver();
  }
  runApp(app);
}
```

Both calls are idempotent. Release builds tree-shake the entire `!kReleaseMode` branch on dart2js (web) and
dart2native (mobile and desktop AOT).

<a name="the-core-fields"></a>
## The core fields

Tapir emits a `wind:` YAML block under each W-widget ref by resolving the element through
`WindDebugRegistry.current?.resolve(element)` before the enricher loop runs. `className`,
`breakpoint`, `brightness`, `platform` and `states` are always present; `bgColor` and `textColor`
appear only when the resolved `WindStyle` carries a non-null `decoration.color` / `color`. A
W-widget with no `className` (an interaction-only widget such as `WAnchor`) gets no block.

| Field | Source | Notes |
|:------|:-------|:------|
| `className` | the widget's `className` | The raw utility string. |
| `breakpoint` | `WindContext.activeBreakpoint` | The widest `screens` entry the width reaches: `sm`, `md`, `lg`, `xl`, `2xl` by default, `base` below the first. |
| `brightness` | `WindContext.theme.brightness` | `light` or `dark`. |
| `platform` | `WindContext.platform` | `web`, `ios`, `android`, `macos`, `windows`, `linux`, or `unknown`. |
| `states` | `WindContext.activeStates` | Pseudo-class states active on the element (e.g. `[hover]`, `[hover, focus]`). |
| `bgColor` | `style.decoration?.color` | `#` plus 6-char RGB hex (opacity dropped, uppercase). |
| `textColor` | `style.color` | `#` plus 6-char RGB hex (opacity dropped, uppercase). |

<a name="example-snapshot-output"></a>
## Example snapshot output

A `WButton` rendered on web at the `md` breakpoint with a hover state active:

```yaml
- ref: e7
  role: button
  label: "Sign In"
  bounds: 240,360,160,40
  wind:
    className: px-4 py-3 bg-blue-500 text-white hover:bg-blue-600
    breakpoint: md
    brightness: light
    platform: web
    states: [hover]
    bgColor: #3B82F6
    textColor: #FFFFFF
```

<a name="test-only-reset"></a>
## Test-only reset

There is no tapir-side reset for wind state: the old `WindTapirIntegration` class no longer
exists. Tests reset the bridge with `WindDebugRegistry.resetForTesting()` from
`wind_kit_diagnostics_contracts`. Production code never calls any reset method.

<a name="cross-package-coupling"></a>
## Cross-package coupling

`wind_kit_diagnostics_contracts` is a hosted dependency of both `tapir` and `wind_kit`; neither
depends on the other. A change to the contracts package is a coordinated bump across the
packages that read it.

<a name="related-documentation"></a>
## Related Documentation

- [enricher-authoring.md](enricher-authoring.md): the `TapirSnapshotEnricher` contract, for data that is per element rather than a global registry.
- [magic-integration.md](magic-integration.md): the Magic enrichers that run after the wind block.
