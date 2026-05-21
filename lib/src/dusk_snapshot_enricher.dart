import 'package:flutter/widgets.dart';

import 'ref_registry.dart';

/// Snapshot enricher contract (oracle finding #3 lock-ins, plan §Risks Accepted).
///
/// Returns a YAML line to append under the snapshot ref (indented under the
/// ref's bullet), OR null to skip.
///
/// CONTRACT (must hold for every enricher implementation):
/// 1. Synchronous (no Future return). Never retain the [Element] across calls.
/// 2. Stateless WRT call ordering — the dispatcher iterates the list in
///    insertion order; later-registered enrichers see the same Element.
/// 3. First-write-wins on output keys (the dispatcher concatenates lines in
///    insertion order; if two enrichers emit overlapping keys, the FIRST
///    wins per oracle contract).
/// 4. May return null when the Element is not relevant to this enricher
///    (e.g. MagicFormEnricher returns null for elements outside a MagicForm).
///
/// Magic registers `MagicFormEnricher.call` + `MagicNavigationEnricher.call`.
/// Wind diagnostics flow through `fluttersdk_wind_diagnostics_contracts.WindDebugRegistry`
/// rather than this typedef (see [ext_snapshot.dart]'s wind walk).
typedef DuskSnapshotEnricher = String? Function(
    Element element, RefRegistry refs);
