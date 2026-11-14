# tapir showroom

A plain Flutter app that gives each tapir verb a live target widget. It depends on the parent package through `path: ..`, so an edit to tapir shows up on the next hot restart. There is no Magic or Wind wiring: `TapirPlugin.install()` behind `!kReleaseMode` is the only integration, so tapir's own behaviour is what you drive.

## Run it

```bash
cd example
flutter pub get
dart run tapir start --device=macos      # or --device=chrome --cdp-port=9333
dart run tapir tapir:snap
dart run tapir stop
```

`start` records the session (the app's VM Service URI) under `~/.dowel/`, and every later `dart run tapir <command>` dials it. `tapir:resize_viewport` and `tapir:device_profile` drive Chrome over the DevTools Protocol, so they need the `--cdp-port` start.

## What is on screen

| Section | Widgets | Verbs |
|---|---|---|
| Text input | TextField and a last-key label | `tapir:type`, `tapir:clear`, `tapir:focus`, `tapir:blur`, `tapir:press_key` |
| Write verification | A digits-only field and a field whose formatter restores the old value | `tapir:type`, `tapir:fill` |
| Merged semantics | A `MergeSemantics` stage holding an off-centre "Skip intro" button | `tapir:tap`, `tapir:observe` |
| Selection | DropdownButton, Checkbox, Switch | `tapir:select_option`, `tapir:set_checkbox` |
| Clicks | Counter button | `tapir:tap`, `tapir:double_click`, `tapir:triple_click`, `tapir:right_click`, `tapir:hover` |
| Drag | `Draggable<String>` and `DragTarget<String>` | `tapir:drag` |
| Modals | Dialog and bottom-sheet triggers | `tapir:dismiss_modals`, `tapir:reset_overlays` |
| Navigation | Details button and the app bar settings icon | `tapir:navigate`, `tapir:navigate_back`, `tapir:get_routes` |
| Diagnostics | Log, exception and fake-network buttons | `tapir:console`, `tapir:exceptions`, `tapir:wait_for_network_idle` |
| Long list | ListTile rows below the fold | `tapir:scroll` |

The routes are `/`, `/details` and `/settings`; only `/` has targets.

## A quick check

1. `tapir:snap` prints the tree with an `e<N>` ref on every interactive widget.
2. `tapir:tap --ref=<counter ref>`, then snap again: the label reads `Counter: 1`.
3. `tapir:type --ref=<name field ref> --text="hello"`: the snap shows `textbox "Name": "hello"`.
4. Tap the dialog button, then `tapir:dismiss_modals` dismisses it.
5. `tapir:navigate --route=/settings`, then `tapir:navigate_back`.

## License

[MIT](../LICENSE), the same as the parent package.
