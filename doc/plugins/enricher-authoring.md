# Authoring a snapshot enricher

`TapirSnapshotEnricher` is the extension point that lets a package or a host app append custom YAML lines under each ref of a `tapir:snap` output.

Enrichers run when the snapshot is taken with `includeEnrichers` on. The Magic integration
ships enrichers out of the box, and anyone can register one. This
guide walks through the typedef, the four-clause contract, the registration surface, and a
short worked example.

- [The typedef](#the-typedef)
- [The four-clause contract](#the-four-clause-contract)
- [Registration](#registration)
- [Worked example: Riverpod provider value enricher](#worked-example-riverpod-provider-value-enricher)
- [Testing your enricher](#testing-your-enricher)
- [Related Documentation](#related-documentation)

<a name="the-typedef"></a>
## The typedef

```dart
typedef TapirSnapshotEnricher =
    String? Function(Element element, RefRegistry refs);
```

An enricher is a plain top-level function (or any compatible callable)
that receives a Flutter `Element` plus the snapshot's `RefRegistry` and
returns either a YAML fragment to append under the ref, or `null` to skip
that element.

**The typedef is frozen.** The signature `String? Function(Element element,
RefRegistry refs)` does not change without a coordinated bump across `tapir` and
`magic_devtools` (which ships the Magic enrichers via `MagicTapirIntegration`). Treat it
as a load-bearing cross-repo contract.

<a name="the-four-clause-contract"></a>
## The four-clause contract

Every enricher implementation MUST honour these clauses:

1. **Synchronous.** No `Future` return. The snapshot extension iterates
   the enricher chain on a single render-tree pass; an async enricher
   would deadlock the dispatcher.
2. **Stateless WRT call ordering.** The dispatcher iterates
   `TapirPlugin.enrichers` in insertion order; later-registered enrichers
   see the same `Element` as earlier ones. An enricher must not mutate
   shared state in a way that affects siblings later in the chain.
3. **First-write-wins on output keys.** When two enrichers emit
   overlapping YAML keys for the same ref, the FIRST one in the chain
   wins. Registration order is therefore precedence order.
4. **Null means skip.** Return `null` when the element is not relevant
   (no matching widget type, no ancestor context, no data available).
   The dispatcher silently drops null returns.

A fifth rule applies to every enricher implementation in practice:
**never retain the `Element` across calls.** The enricher receives the
element by reference; capturing it in a closure, a static field, or any
external collection produces a leak and can silently widen the actionability
gate's view of the live tree on the next snap.

<a name="registration"></a>
## Registration

Enrichers register against the `TapirPlugin.enrichers` list, mutated in
place. The list is read live on every snapshot call, so mid-session
registrations are picked up immediately.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tapir/tapir.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    TapirPlugin.install();
    TapirPlugin.enrichers.add(myCustomEnricher);
  }
  runApp(app);
}
```

When you ship a reusable integration (rather than a one-off in `main`),
follow the `MagicTapirIntegration` pattern: a private constructor, an
`install()` static that guards against duplicate adds with a static bool,
and a `resetForTesting()` static that removes the enricher and clears the
guard. `wind_kit` takes a different path (the neutral `WindDebugRegistry`
bridge, read by tapir at snap time without an enricher); pick the enricher
pattern when your data is per-element and the bridge pattern when your
data is a global registry the consumer installs once.

<a name="worked-example-riverpod-provider-value-enricher"></a>
## Worked example: Riverpod provider value enricher

Surface the current value of a `StateProvider<int>` (e.g. a session
counter) next to every snapshot ref. The enricher reads the provider once
per snap from a host-supplied `ProviderContainer`, formats the value, and
emits a `riverpodCounter:` line.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapir/tapir.dart';

/// Host-owned counter provider. Real apps would define this elsewhere.
final counterProvider = StateProvider<int>((ref) => 0);

class RiverpodTapirIntegration {
  RiverpodTapirIntegration._();

  static bool _installed = false;
  static ProviderContainer? _container;

  /// Wire the enricher. Pass the host's [ProviderContainer] so the
  /// enricher can read provider values synchronously at snap time.
  static void install(ProviderContainer container) {
    if (_installed) return;
    _installed = true;
    _container = container;
    TapirPlugin.enrichers.add(riverpodCounterEnricher);
  }

  @visibleForTesting
  static void resetForTesting() {
    TapirPlugin.enrichers.remove(riverpodCounterEnricher);
    _container = null;
    _installed = false;
  }
}

/// Emits `riverpodCounter: <value>` for every element when a container
/// is wired. Element-independent (the value is global), but kept as a
/// per-element enricher so the YAML emitter consistently surfaces it
/// next to each ref. Returns null when no container has been installed.
String? riverpodCounterEnricher(Element element, RefRegistry refs) {
  final container = RiverpodTapirIntegration._container;
  if (container == null) return null;
  final int value = container.read(counterProvider);
  return 'riverpodCounter: $value';
}
```

A few details worth noting:

- The enricher reads from a module-static `_container` rather than
  capturing the container in a closure. This is the canonical pattern
  when an enricher needs side-channel state; it keeps the typedef
  intact and lets `resetForTesting()` cleanly drop the reference.
- `container.read(counterProvider)` is the synchronous Riverpod read.
  A `.watch` would not compile here (the enricher is not a widget) and
  would also violate clause 1 of the contract.
- The `element` parameter is unused. That is fine; per-element
  enrichers may emit element-independent annotations. The dispatcher
  still walks the element tree, which keeps the line attached to the
  correct ref in the YAML output.

<a name="testing-your-enricher"></a>
## Testing your enricher

Drive the enricher directly from a widget test:

```dart
testWidgets('riverpodCounterEnricher surfaces the current value',
    (tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  RiverpodTapirIntegration.install(container);
  addTearDown(RiverpodTapirIntegration.resetForTesting);

  await tester.pumpWidget(const SizedBox.shrink());
  final element = tester.element(find.byType(SizedBox));

  expect(riverpodCounterEnricher(element, RefRegistry.instance),
      'riverpodCounter: 0');

  container.read(counterProvider.notifier).state = 42;
  expect(riverpodCounterEnricher(element, RefRegistry.instance),
      'riverpodCounter: 42');
});
```

For tests that exercise the enricher inside the full snapshot pipeline,
trigger a real `tapir:snap` via the VM Service extension (see the tapir
extension tests under `test/src/extensions/` for the pattern).

<a name="related-documentation"></a>
## Related Documentation

- [magic-integration.md](magic-integration.md): the multi-enricher reference (form
  fields, controllers, gates, middleware, auth, broadcast state, and crumbs ring buffers).
- [wind-integration.md](wind-integration.md): the bridge pattern for global state, which
  surfaces breakpoint, brightness, platform and pseudo-class states without an enricher.
