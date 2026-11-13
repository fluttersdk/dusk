# tapir showroom

A vanilla Flutter app that gives every tapir CLI command a live target widget on one route. The app resolves `tapir` directly from the sibling source tree via `path: ../`, so any edit to the parent package is immediately reflected on the next hot restart. Magic / Wind enricher integration is out of scope; this is a plain `runApp` entry point wired manually so tapir's own behaviour is the only thing under test.

## How to run

```bash
cd example
flutter pub get
dart run tapir start --device=macos      # or --device=chrome --cdp-port=9333
```

`dart run tapir start` records the VM Service URI into `~/.dowel/state.json`; every subsequent `dart run tapir <cmd>` reuses it. `start --device=chrome --cdp-port=<N>` is required for `tapir:resize` and `tapir:device` since both drive Chrome via the DevTools Protocol.

## Sections

Each section on the home route exposes one widget family that the matching tapir command targets:

| Section | Widgets | Tapir commands |
|---------|---------|---------------|
| Text input | TextField + last-key label | `tapir:type`, `tapir:clear`, `tapir:focus`, `tapir:blur`, `tapir:press_key` |
| Write verification | Digits-only "Quantity" TextField + "Reverting" TextField whose formatter restores the old value on the next frame | `tapir:type`, `tapir:fill` |
| Merged semantics | 300x120 `MergeSemantics` stage that pauses on any tap, holding an off-centre "Skip intro" button; `tapir:tap` must skip, not pause (anilcancakir/tapir#60) | `tapir:tap`, `tapir:observe` |
| Selection | DropdownButton + Checkbox + Switch | `tapir:set_checkbox`, `tapir:select_option` |
| Clicks | Counter ElevatedButton | `tapir:tap`, `tapir:dblclick`, `tapir:triple_click`, `tapir:right_click`, `tapir:hover` |
| Drag | `Draggable<String>` + `DragTarget<String>` | `tapir:drag` |
| Modals | Dialog + bottom-sheet triggers | `tapir:modal` |
| Navigation | Go-details button + appbar settings icon | `tapir:navigate`, `tapir:navigate_back`, `tapir:get_routes` |
| Diagnostics | Emit-log + throw-exception + fake-network buttons | `tapir:console`, `tapir:exceptions`, `tapir:wait_for_network_idle` |
| Long list | 30 ListTile rows below the fold | `tapir:scroll` |
| (anywhere) | Whole semantic tree | `tapir:snap`, `tapir:screenshot`, `tapir:find`, `tapir:observe`, `tapir:wait` |
| (lifecycle) | n/a | `tapir:install`, `tapir:doctor`, `tapir:hot_reload_and_snap`, `tapir:close_app` |
| (Chrome only) | n/a | `tapir:resize`, `tapir:device` (need `--cdp-port`) |

Three named routes (`/`, `/details`, `/settings`) cover navigation tools; nothing on `/details` or `/settings` needs targeting.

## Manual QA checklist

- Boot the app via `dart run tapir start --device=macos`.
- `dart run tapir tapir:snap` → returns the semantic tree with stable `eN` refs for every interactive widget.
- Tap the counter button via `tapir:tap --ref=<eN>` and re-snap; the label flips to `Counter: 1`.
- `tapir:type --ref=<name-field-ref> --text="hello"` → re-snap shows `textbox "Name": "hello"`.
- `tapir:set_checkbox --ref=<checkbox-ref> --value=true` and `--ref=<switch-ref> --value=true` both fire.
- `tapir:select_option --ref=<dropdown-ref> --value=beta` flips the dropdown label.
- `tapir:tap` the dialog button, then `tapir:modal` dismisses it.
- `tapir:navigate --route=/settings` then `tapir:navigate_back` cycles routes.
- `tapir:hot_reload_and_snap --no-screenshot` returns `{"reloaded":true,"durationMs":<N>}` and a fresh snapshot.
- `tapir:close_app` ends the showroom on macOS / desktop. (Web tabs cannot be closed programmatically; use `dart run tapir stop` instead.)

## Path dependency note

This example depends on the parent tapir package via `path: ..`. Source edits to the parent require nothing more than `dart run tapir hot-restart` (or pressing `R` in flutter run) to surface. Downstream consumers that install from pub.dev use the hosted `^0.0.2` constraint instead. `dowel` and `wind_kit_diagnostics_contracts` arrive transitively from pub.dev, so the consumer pubspec stays single-line.

## License

[MIT](../LICENSE); same license as the parent `tapir` package.
