# dusk:reset_overlays

Return the app to a known clean screen by dismissing every modal, pressing Escape, and tapping a Cancel/Dismiss affordance as a fallback. `dusk:reset_overlays` promotes the manual overlay-reset dance (dismiss + Escape + Cancel-tap) into one idempotent command, so an agent can reliably clear stuck dialogs, bottom sheets, dropdown menus, and barrier modals between flows without composing the steps by hand.

---

## Table of contents

- [Synopsis](#synopsis)
- [Layers](#layers)
- [Returns](#returns)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:reset_overlays
```

`dusk:reset_overlays` requires a running Flutter session (`CommandBoot.connected`). It takes no arguments, calls `ext.dusk.reset_overlays`, and prints the JSON result. It is idempotent: calling it when nothing is open is a safe no-op.

---

<a name="layers"></a>
## Layers

Three escalating layers run in order, each a no-op when the prior already cleared the overlays:

1. **Dismiss modals** ; pops every `PopupRoute` (dialogs, bottom sheets, popups) across every `NavigatorState`, reusing the same `dismissAllModals` path as `dusk:modal`. The page navigation stack is never touched.
2. **Escape key** ; dispatches an `Escape` key down + up through `HardwareKeyboard`, dismissing overlays driven by the dismiss shortcut that are NOT `PopupRoute`s (custom `OverlayEntry` panels, dropdown menus closed via `Shortcuts`).
3. **Cancel/Dismiss tap** ; only attempted when an overlay still appears present. Finds the first tappable Semantics node whose label matches `Cancel`, `Dismiss`, `Close`, `OK`, or `Done` (case-insensitive) and synthesizes a tap at its center, for modal barriers that require an explicit affordance to close.

---

<a name="returns"></a>
## Returns

| Exit code | Meaning |
|-----------|---------|
| `0` | Reset attempted. Emits the JSON result. |
| non-zero | VM Service handler returned an error (no running app at the recorded URI, unexpected failure). |

**Success envelope:**

```json
{
  "popped": 2,
  "escaped": true,
  "dismissTapped": false
}
```

- `popped` ; number of `PopupRoute`s dismissed by layer 1.
- `escaped` ; whether the Escape key press was dispatched.
- `dismissTapped` ; whether layer 3 tapped a Cancel/Dismiss affordance.

On a clean tree all three indicate no work was done (`popped: 0`, `dismissTapped: false`), confirming idempotency.

---

<a name="examples"></a>
## Examples

### 1. Reset overlays between test flows

```bash
dart run fluttersdk_dusk dusk:reset_overlays
```

```json
{"popped":1,"escaped":true,"dismissTapped":false}
```

### 2. Speculative reset before navigating

```bash
dart run fluttersdk_dusk dusk:reset_overlays
dart run fluttersdk_dusk dusk:navigate --route=/dashboard
```

Safe to call even when nothing is open; the no-op path returns `popped: 0`.

---

<a name="see-also"></a>
## See also

- [dusk:modal](dusk-snap.md): the underlying dismiss-modals path; `dusk:reset_overlays` adds Escape + Cancel-tap fallback on top.
- [dusk:tap](dusk-tap.md): tap a specific Cancel button by ref when you want precise control.
- [dusk:snap](dusk-snap.md): re-snapshot after a reset; refs from before the reset are stale.
