# fluttersdk_dusk showroom

A vanilla Flutter app that gives every dusk CLI command a live target widget on one route. The app resolves `fluttersdk_dusk` directly from the sibling source tree via `path: ../`, so any edit to the parent package is immediately reflected on the next hot restart. Magic / Wind enricher integration is out of scope; this is a plain `runApp` entry point wired manually so dusk's own behaviour is the only thing under test.

## How to run

```bash
cd example
flutter pub get
dart run fluttersdk_dusk start --device=macos      # or --device=chrome --cdp-port=9333
```

`dart run fluttersdk_dusk start` records the VM Service URI into `~/.artisan/state.json`; every subsequent `dart run fluttersdk_dusk <cmd>` reuses it. `start --device=chrome --cdp-port=<N>` is required for `dusk:resize` and `dusk:device` since both drive Chrome via the DevTools Protocol.

## Sections

Each section on the home route exposes one widget family that the matching dusk command targets:

| Section | Widgets | Dusk commands |
|---------|---------|---------------|
| Text input | TextField + last-key label | `dusk:type`, `dusk:clear`, `dusk:focus`, `dusk:blur`, `dusk:press_key` |
| Selection | DropdownButton + Checkbox + Switch | `dusk:set_checkbox`, `dusk:select_option` |
| Clicks | Counter ElevatedButton | `dusk:tap`, `dusk:dblclick`, `dusk:triple_click`, `dusk:right_click`, `dusk:hover` |
| Drag | `Draggable<String>` + `DragTarget<String>` | `dusk:drag` |
| Modals | Dialog + bottom-sheet triggers | `dusk:modal` |
| Navigation | Go-details button + appbar settings icon | `dusk:navigate`, `dusk:navigate_back`, `dusk:get_routes` |
| Diagnostics | Emit-log + throw-exception + fake-network buttons | `dusk:console`, `dusk:exceptions`, `dusk:wait_for_network_idle` |
| Long list | 30 ListTile rows below the fold | `dusk:scroll` |
| (anywhere) | Whole semantic tree | `dusk:snap`, `dusk:screenshot`, `dusk:find`, `dusk:observe`, `dusk:wait` |
| (lifecycle) | n/a | `dusk:install`, `dusk:doctor`, `dusk:hot_reload_and_snap`, `dusk:close_app` |
| (Chrome only) | n/a | `dusk:resize`, `dusk:device` (need `--cdp-port`) |

Three named routes (`/`, `/details`, `/settings`) cover navigation tools; nothing on `/details` or `/settings` needs targeting.

## Manual QA checklist

- Boot the app via `dart run fluttersdk_dusk start --device=macos`.
- `dart run fluttersdk_dusk dusk:snap` → returns the semantic tree with stable `eN` refs for every interactive widget.
- Tap the counter button via `dusk:tap --ref=<eN>` and re-snap; the label flips to `Counter: 1`.
- `dusk:type --ref=<name-field-ref> --text="hello"` → re-snap shows `textbox "Name": "hello"`.
- `dusk:set_checkbox --ref=<checkbox-ref> --value=true` and `--ref=<switch-ref> --value=true` both fire.
- `dusk:select_option --ref=<dropdown-ref> --value=beta` flips the dropdown label.
- `dusk:tap` the dialog button, then `dusk:modal` dismisses it.
- `dusk:navigate --route=/settings` then `dusk:navigate_back` cycles routes.
- `dusk:hot_reload_and_snap --no-screenshot` returns `{"reloaded":true,"durationMs":<N>}` and a fresh snapshot.
- `dusk:close_app` ends the showroom on macOS / desktop. (Web tabs cannot be closed programmatically; use `dart run fluttersdk_dusk stop` instead.)

## Path dependency note

This example depends on the parent dusk package via `path: ..`. Source edits to the parent require nothing more than `dart run fluttersdk_dusk hot-restart` (or pressing `R` in flutter run) to surface. Downstream consumers that install from pub.dev use the hosted `^0.0.2` constraint instead. `fluttersdk_artisan` and `fluttersdk_wind_diagnostics_contracts` arrive transitively from pub.dev, so the consumer pubspec stays single-line.

## License

[MIT](../LICENSE); same license as the parent `fluttersdk_dusk` package.
