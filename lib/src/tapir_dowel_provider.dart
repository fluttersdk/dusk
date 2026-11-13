import 'package:dowel/dowel.dart';

import 'commands/tapir_blur_command.dart';
import 'commands/tapir_clear_command.dart';
import 'commands/tapir_close_app_command.dart';
import 'commands/tapir_console_command.dart';
import 'commands/tapir_dblclick_command.dart';
import 'commands/tapir_device_command.dart';
import 'commands/tapir_focus_command.dart';
import 'commands/tapir_right_click_command.dart';
import 'commands/tapir_run_command.dart';
import 'commands/tapir_triple_click_command.dart';
import 'commands/tapir_doctor_command.dart';
import 'commands/tapir_drag_command.dart';
import 'commands/tapir_exceptions_command.dart';
import 'commands/tapir_fill_command.dart';
import 'commands/tapir_find_command.dart';
import 'commands/tapir_get_routes_command.dart';
import 'commands/tapir_hot_reload_and_snap_command.dart';
import 'commands/tapir_hover_command.dart';
import 'commands/tapir_install_command.dart';
import 'commands/tapir_modal_command.dart';
import 'commands/tapir_navigate_back_command.dart';
import 'commands/tapir_navigate_command.dart';
import 'commands/tapir_observe_command.dart';
import 'commands/tapir_perf_begin_command.dart';
import 'commands/tapir_perf_campaign_command.dart';
import 'commands/tapir_perf_compare_command.dart';
import 'commands/tapir_perf_end_command.dart';
import 'commands/tapir_perf_insight_command.dart';
import 'commands/tapir_perf_run_command.dart';
import 'commands/tapir_perf_trace_command.dart';
import 'commands/tapir_press_key_command.dart';
import 'commands/tapir_reset_overlays_command.dart';
import 'commands/tapir_resize_command.dart';
import 'commands/tapir_screenshot_command.dart';
import 'commands/tapir_scroll_command.dart';
import 'commands/tapir_select_option_command.dart';
import 'commands/tapir_set_checkbox_command.dart';
import 'commands/tapir_snap_command.dart';
import 'commands/tapir_tap_command.dart';
import 'commands/tapir_type_command.dart';
import 'commands/tapir_wait_command.dart';
import 'commands/tapir_wait_for_network_idle_command.dart';

// Schema properties shared by the verbs that embed a post-action snapshot or
// run the actionability gate. dowel validates every call against the schema
// and each schema is closed (`additionalProperties: false`), so a knob a handler
// reads has to be listed here to be passable over MCP. The perf runner and the
// CLI call the extensions directly: coordinate dispatch (x, y, toX, toY, drag
// dx/dy), `reportPoint`, perf_end's `full` and screenshot's `geometry` are
// theirs, and `tapir:resize --hold` keeps a CDP session an MCP call cannot hold.
// None of them is part of the MCP surface.

/// `snapshot`: the post-action snapshot mode, overriding `includeSnapshot`.
const Map<String, dynamic> _kSnapshotProperty = <String, dynamic>{
  'type': 'string',
  'enum': <String>['full', 'diff', 'none'],
  'description': 'Post-action snapshot: the whole tree (`full`, the default), '
      'only the lines the action changed since your last snapshot (`diff`), '
      'or none. Overrides `includeSnapshot`.',
};

/// `includeSnapshot` for a verb that embeds the snapshot unless told not to.
const Map<String, dynamic> _kIncludeSnapshotProperty = <String, dynamic>{
  'type': 'boolean',
  'description': 'Embed the post-action snapshot (default true). `snapshot` '
      'overrides it.',
};

/// `checkStable`: the gate's stability precondition.
const Map<String, dynamic> _kCheckStableProperty = <String, dynamic>{
  'type': 'boolean',
  'description': 'Run the Stable actionability gate (default true).',
};

/// `checkReceivesEvents`: the gate's hit-test precondition.
const Map<String, dynamic> _kCheckReceivesEventsProperty = <String, dynamic>{
  'type': 'boolean',
  'description': 'Run the Receives-Events actionability gate (default true).',
};

/// Contributes tapir:* commands and MCP tool descriptors to the dowel
/// dispatcher.
///
/// Host integration:
/// ```dart
/// // lib/config/app.dart
/// final appConfig = {
///   'dowel': {
///     'providers': [TapirDowelProvider.new],
///   },
/// };
/// ```
///
/// Alpha-2 ships 11 CLI commands (snap / tap / screenshot from alpha-1 +
/// install + type / scroll / wait / hover / drag / modal added in Wave 2 +
/// doctor added in Wave 4b Step 21).
///
/// MCP tools: 17 descriptors. The original 6 from alpha-1 (snap / tap /
/// screenshot / hover / drag / type) are preserved verbatim; the 10 new
/// descriptors (scroll / wait_for / dismiss_modals / navigate /
/// navigate_back / get_routes / press_key / select_option / evaluate /
/// close_app) come from Wave 2's handler steps; tapir_find (Step 16) adds
/// the Playwright-Locator-style query-handle resolver as the 17th.
class TapirDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'tapir';

  @override
  List<DowelCommand> commands() => <DowelCommand>[
        // Alpha-1.
        TapirSnapCommand(),
        TapirTapCommand(),
        TapirScreenshotCommand(),
        // Alpha-2 Step 11.
        TapirInstallCommand(),
        // Alpha-2 Step 12 (six standard verbs).
        TapirTypeCommand(),
        TapirScrollCommand(),
        TapirWaitCommand(),
        TapirHoverCommand(),
        TapirDragCommand(),
        TapirModalCommand(),
        // Alpha-2 Step 21.
        TapirDoctorCommand(),
        // CLI symmetry pass: every E2E-driver MCP tool has a matching
        // CLI command so the two surfaces expose identical capabilities.
        // Seven verbs land alongside their pre-existing ext.tapir.*
        // handlers + tapir_* MCP descriptors. tapir_evaluate intentionally
        // stays MCP-only: magic_tinker (the dedicated REPL package) owns
        // the actual evaluate-via-VM-Service implementation and ships
        // `tinker --eval` as the CLI surface; duplicating it under
        // `tapir:` would split the evaluate contract across two packages.
        TapirNavigateCommand(),
        TapirNavigateBackCommand(),
        TapirGetRoutesCommand(),
        TapirPressKeyCommand(),
        TapirSelectOptionCommand(),
        TapirCloseAppCommand(),
        TapirFindCommand(),
        // Step 3.4: network-idle waiter wired against
        // CrumbsStore.pendingHttpCount via pendingHttpCountReader.
        TapirWaitForNetworkIdleCommand(),
        // Step 3.5: crumbs readers + double-click + checkbox setter.
        TapirConsoleCommand(),
        TapirExceptionsCommand(),
        TapirDblclickCommand(),
        TapirSetCheckboxCommand(),
        // Wave 4 Step 4.1: structured candidate list (Stagehand observe-once-
        // act-many; no server-side LLM).
        TapirObserveCommand(),
        // Wave 4 Step 4.2: fused round-trip (mcp_flutter's
        // `fmt_hot_reload_and_capture` pattern). Reload lives CLI-side
        // because an in-isolate handler cannot reload itself.
        TapirHotReloadAndSnapCommand(),
        // P4 (Playwright parity): explicit focus management + right-click +
        // triple-click + clear-text.
        TapirFocusCommand(),
        TapirBlurCommand(),
        TapirClearCommand(),
        TapirRightClickCommand(),
        TapirTripleClickCommand(),
        // Wave 4 Step 6+7 (CDP): device emulation commands.
        TapirResizeCommand(),
        TapirDeviceCommand(),
        // D7: harness workarounds promoted to first-class commands.
        // tapir:fill = focus + clear + type + settle + stale-retry in one call.
        // tapir:reset_overlays = dismiss + Escape + Cancel-tap fallback.
        TapirFillCommand(),
        TapirResetOverlaysCommand(),
        // Performance attribution: one session, opened and closed around a
        // driven interaction.
        TapirPerfBeginCommand(),
        TapirPerfEndCommand(),
        TapirPerfInsightCommand(),
        // Host-side perf: the scenario runner, the run-file compare and the
        // Chrome Trace export.
        TapirPerfRunCommand(),
        TapirPerfCompareCommand(),
        TapirPerfTraceCommand(),
        // The whole campaign, one cold start per scenario (CLI only).
        TapirPerfCampaignCommand(),
        // Batch: several verbs on one connection, one round trip.
        TapirRunCommand(),
      ];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
        // ---------------------------------------------------------------------
        // 1. Snapshot: captures the Semantics tree, no required params.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_snap',
          description: 'Capture a YAML snapshot of the running Flutter app\'s '
              'Semantics tree with stable `[ref=eN]` tokens.\n'
              '\n'
              'Walks the app\'s Semantics tree from the root, emits one '
              'YAML node per widget with role / label / actions / bounds, '
              'and assigns each node a stable `eN` ref. Every action tool '
              '(tapir_tap, tapir_hover, tapir_drag, tapir_type) takes one of '
              'these refs to identify its target. Call this FIRST, then '
              'pass the returned ref tokens to subsequent action calls.\n'
              '\n'
              'Nodes inside a currently-overflowing render ancestor carry '
              'an additive `overflow: true` sub-line (live '
              '`RenderFlex.toStringShort()` check). This is a current-state '
              'signal only; call tapir_exceptions for the full non-fatal '
              'error history including overflow details.\n'
              '\n'
              'When non-fatal render/build FlutterErrors have been captured '
              '(e.g. a ParentDataWidget misuse that makes a button render but '
              'ignore taps), the response adds a `renderErrors` block '
              '(count + recent messages). Treat a non-zero count as the likely '
              'reason an action against a visible widget silently no-ops; call '
              'tapir_exceptions for the full message + stack.\n'
              '\n'
              'Usage:\n'
              '- Call before any tapir_* action tool; refs become stale '
              'after navigation, modal open/close, or significant widget '
              'tree rebuild.\n'
              '- Pass `depth: <n>` to limit tree traversal depth (default '
              'unlimited). Useful when the tree is huge and you only need '
              'the visible region.\n'
              '- Narrow instead of reading everything: `within: "e12"` walks '
              'one subtree, `interactiveOnly: true` drops the prose, '
              '`grep: "Sign in"` keeps only matches and the path to them. A '
              'full tree is the wrong default answer to most questions, and '
              'on a shell whose sidebar repeats page labels it is also the '
              'misleading one.\n'
              '- A ref line ends with ` [offscreen]` (outside the viewport) '
              'or ` [occluded]` (another widget covers its center) when '
              'true. An invalid `grep` regex matches as literal text and '
              'the response carries `grepLiteral: true`.\n'
              '- Returns YAML; the model parses ref tokens out of the '
              'shape `[ref=e<N>]` next to each widget.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'depth': <String, dynamic>{
                'type': 'integer',
                'description': 'Max tree-traversal depth from the root. '
                    'Omit for full tree. Use a small number (5-10) when '
                    'snapshotting only the focused screen.',
              },
              'within': <String, dynamic>{
                'type': 'string',
                'description': 'Scope the walk to one subtree: the `e<N>` '
                    'ref of the region to read. Reach for this when a label '
                    'repeats across the shell, which it usually does (a '
                    'sidebar item and the page it opens share one), because '
                    'an unscoped lookup resolves the nav item and you end up '
                    'measuring the sidebar.',
              },
              'interactiveOnly': <String, dynamic>{
                'type': 'boolean',
                'description': 'Emit only nodes that carry a ref (buttons, '
                    'text fields, links, anything tappable) and drop the '
                    'plain text lines. Default false. Use when the next step '
                    'is an action and the prose is not the question.',
              },
              'grep': <String, dynamic>{
                'type': 'string',
                'description': 'Emit only nodes whose label or value matches '
                    'this regular expression, plus the ancestors leading to '
                    'them. Ancestors are kept because they carry the refs '
                    'you act on: a matching text line has none of its own.',
              },
              'includeEnrichers': <String, dynamic>{
                'type': 'boolean',
                'description': 'Add the Magic and Wind enricher lines under '
                    'each ref (default false). A boolean here; '
                    '`tapir_observe` takes `"true"`, `"false"` or `"full"`.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.snap',
        ),
        // ---------------------------------------------------------------------
        // 2. Tap: pointer Down+50ms+Up at the widget identified by ref.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_tap',
          description: 'Tap a widget by ref token from a prior tapir_snap.\n'
              '\n'
              'Synthesizes a pointer Down + 50ms hold + Up sequence at the '
              'center of the widget identified by `ref`. Triggers '
              '`GestureDetector.onTap`, `InkWell.onTap`, button onPressed, '
              'and any other gesture handler bound to that widget. For '
              'TextField widgets the tap also requests keyboard focus.\n'
              '\n'
              'Usage:\n'
              '- Call tapir_snap first to get a ref token; the ref string '
              'has shape `e<N>`.\n'
              '- Returns the ref of the tapped widget on success; errors '
              'when the ref is unknown or stale (re-snap to refresh).\n'
              '- For drag use tapir_drag; for typing use tapir_type after '
              'tapir_tap to focus the field.\n'
              '- Every response carries an `effect` block: '
              '`{kind: "treeChanged", changed: bool}`. `changed: false` means '
              "the target's own route and semantics subtree are byte-"
              'identical after the tap, so nothing the agent can see '
              'happened. Read it before concluding the app is broken.\n'
              '- A hidden or minimised desktop window is woken first (tapir '
              'delivers `resumed` on the lifecycle channel) and the response '
              'carries `framesForced: true`; when it cannot be woken the '
              'response carries a `warnings` block instead.\n'
              '- A stale `e<N>` ref is relocated by label when the live tree '
              'has the same number of matches as at snapshot time, and the '
              'response lists it under `reresolved`.\n'
              '- `snapshot: "diff"` returns only the snapshot lines the tap '
              'changed since your last tapir_snap (`- old` / `+ new`, then '
              '`(K of N lines changed)`); `"none"` drops it.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token from a prior tapir_snap '
                    'call. Shape: `e<N>` (e.g. `e5`, `e23`).',
              },
              'snapshot': <String, dynamic>{
                'type': 'string',
                'enum': <String>['full', 'diff', 'none'],
                'description': 'Post-tap snapshot: the whole tree (`full`, '
                    'the default), only the changed lines (`diff`), or none.',
              },
              'retarget': <String, dynamic>{
                'type': 'boolean',
                'description': 'Default true: a tap on a merged boundary goes '
                    'to its one labelled control. Pass false to tap the '
                    "boundary's centre instead.",
              },
              'until': <String, dynamic>{
                'type': 'string',
                'description': 'After the tap settles, poll the live element '
                    'tree for a Text whose data equals this value and add an '
                    '`untilMatched` boolean to the response. Omit to keep the '
                    'response shape unchanged.',
              },
              'untilTimeoutMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Timeout in milliseconds for the `until` poll '
                    '(default 3000). Ignored when `until` is omitted.',
              },
              'includeSnapshot': _kIncludeSnapshotProperty,
              'checkStable': _kCheckStableProperty,
              'checkReceivesEvents': _kCheckReceivesEventsProperty,
            },
            'required': <String>['ref'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.tap',
        ),
        // ---------------------------------------------------------------------
        // 3. Screenshot: captures a JPEG/PNG frame, no required params.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_screenshot',
          description: 'Capture a screenshot of the running Flutter app as a '
              'base64-encoded image.\n'
              '\n'
              'Renders the current frame to a JPEG or PNG and returns the '
              'image bytes inline so the model can see the UI directly. '
              'This MCP tool always dispatches the in-isolate '
              '`ext.tapir.screenshot` extension.\n'
              '\n'
              'Web limitation: the in-isolate path can hang under '
              'CanvasKit+DWDS (the toImage() future never completes). For '
              'reliable web screenshots, run the CLI command '
              '`tapir:screenshot --output=<path>` instead: when dowel was '
              'started with `--cdp-port`, the CLI falls back to CDP '
              '`Page.captureScreenshot`, and it honours `--ref` / `--rect` '
              'there by resolving the region first and clipping the capture. '
              'That CDP fallback is CLI-only; it does not apply to this MCP '
              'tool.\n'
              '\n'
              'A hidden or minimised desktop window is woken before the '
              'capture, so the image is a fresh frame rather than the last '
              'cached one; the response then carries `framesForced: true`.\n'
              '\n'
              'Usage:\n'
              '- No required params; defaults to the whole viewport as JPEG '
              'at quality 70.\n'
              '- Pass `format: "png"` for a lossless (larger) payload.\n'
              '- Pass `ref` (an e<N> from tapir_snap or a q<N> from tapir_find) '
              'to capture ONLY that widget. This is the cheap way to look at '
              'one component: a full-screen capture of a tall page costs far '
              'more tokens and buries the thing you are checking.\n'
              '- Add `rect: "x,y,w,h"` (logical px, relative to the ref\'s '
              'top-left) to narrow further. `rect` requires `ref`.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'format': <String, dynamic>{
                'type': 'string',
                'enum': <String>['jpeg', 'png'],
                'description': 'Image format. `jpeg` (default) is smaller '
                    '(good for quick visual checks); `png` is lossless but '
                    'larger (use when pixel-perfect detail matters).',
              },
              'quality': <String, dynamic>{
                'type': 'integer',
                'description': 'JPEG quality 0-100 (higher is better). '
                    'Default 70. Ignored when format is `png`.',
              },
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Capture only this widget. An `e<N>` token '
                    'from tapir_snap or a `q<N>` handle from tapir_find. Omit '
                    'to capture the whole viewport.',
              },
              'rect': <String, dynamic>{
                'type': 'string',
                'description': 'Sub-rect `"x,y,w,h"` in logical pixels, '
                    'relative to the ref\'s top-left. Requires `ref`; '
                    'passing it alone is an error rather than a silent '
                    'full-frame capture.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.screenshot',
        ),
        // ---------------------------------------------------------------------
        // 4. Hover: PointerHoverEvent (mouse kind) at the widget center.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_hover',
          description: 'Hover a mouse cursor over a widget by ref token (mouse-'
              'only, no touch equivalent).\n'
              '\n'
              'Synthesizes a `PointerHoverEvent` of `PointerDeviceKind.'
              'mouse` at the center of the widget identified by `ref`. '
              'Triggers `MouseRegion.onEnter`, tooltip reveal, hover '
              'state changes. Web + desktop apps only; mobile devices '
              'ignore hover events.\n'
              '\n'
              'Usage:\n'
              '- Use to reveal tooltips, dropdown previews, or hover-'
              'state widgets before tapir_tap.\n'
              '- Call tapir_snap first to get a ref token.\n'
              '- No-op on touch-only devices (Android, iOS).',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token from a prior tapir_snap '
                    'call. Shape: `e<N>`.',
              },
              'snapshot': _kSnapshotProperty,
              'includeSnapshot': _kIncludeSnapshotProperty,
              'checkStable': _kCheckStableProperty,
              'checkReceivesEvents': _kCheckReceivesEventsProperty,
            },
            'required': <String>['ref'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.hover',
        ),
        // ---------------------------------------------------------------------
        // 5. Drag: Down+5xMove+Up sequence from startRef to endRef.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_drag',
          description: 'Drag from one widget to another by ref tokens.\n'
              '\n'
              'Synthesizes a pointer Down + 5x intermediate Move events + '
              'Up sequence from `startRef`\'s center to `endRef`\'s '
              'center. Use for reorder lists, slider scrubbing, drawer '
              'pulls, swipe-to-dismiss gestures.\n'
              '\n'
              'Usage:\n'
              '- Both refs come from tapir_snap; widget positions are '
              'frozen at snap time.\n'
              '- For pure-direction swipes without a target widget, use '
              'tapir_scroll (when available) or wrap a region in tapir_snap '
              'and use a phantom endRef.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'startRef': <String, dynamic>{
                'type': 'string',
                'description': 'Source widget ref token (`e<N>`). The '
                    'drag begins at this widget\'s center.',
              },
              'endRef': <String, dynamic>{
                'type': 'string',
                'description': 'Target widget ref token (`e<N>`). The '
                    'drag ends at this widget\'s center.',
              },
              'snapshot': _kSnapshotProperty,
              'includeSnapshot': _kIncludeSnapshotProperty,
              'checkStable': _kCheckStableProperty,
              'checkReceivesEvents': _kCheckReceivesEventsProperty,
            },
            'required': <String>['startRef', 'endRef'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.drag',
        ),
        // ---------------------------------------------------------------------
        // 6. Type: sets text into a focused text field identified by ref.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_type',
          description: 'Type text into a TextField widget by ref token.\n'
              '\n'
              'Targets the `TextField` / `TextFormField` widget identified '
              'by `ref` and fires `userUpdateTextEditingValue` so '
              '`onChanged` callbacks fire and form validators run. Falls '
              'back to direct controller mutation when the editable cannot '
              'accept input events. Replaces existing text (does not '
              'append).\n'
              '\n'
              'Usage:\n'
              '- Call tapir_tap on the field FIRST to focus it, then '
              'tapir_type to enter text.\n'
              '- To clear a field, pass `text: ""`.\n'
              '- Submits character by character via the keyboard event '
              'pipeline; multi-line text uses `\\n` line breaks.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'TextField widget ref token (`e<N>`).',
              },
              'text': <String, dynamic>{
                'type': 'string',
                'description': 'Text to enter. Replaces existing field '
                    'content. Pass empty string to clear.',
              },
              'snapshot': _kSnapshotProperty,
              'includeSnapshot': _kIncludeSnapshotProperty,
              'checkStable': _kCheckStableProperty,
              'checkReceivesEvents': _kCheckReceivesEventsProperty,
            },
            'required': <String>['ref', 'text'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.type',
        ),
        // ---------------------------------------------------------------------
        // 7. Scroll: drives a Scrollable widget identified by ref.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_scroll',
          description: 'Scroll a Scrollable widget by ref token.\n'
              '\n'
              'Drives the nearest `Scrollable` ancestor of the widget '
              'identified by `ref` to bring lazily-built children into '
              'view, page through long lists, or reveal off-screen content '
              'before a follow-up tapir_tap. Pair with tapir_snap before AND '
              'after the scroll: post-scroll refs differ from pre-scroll '
              'refs because new widgets enter the Semantics tree.\n'
              '\n'
              'Usage:\n'
              '- Pass `ref` of any widget inside (or below) the target '
              'Scrollable; the extension walks up to the nearest '
              '`Scrollable` ancestor. Without a `ref` it scrolls the first '
              'Scrollable it finds.\n'
              '- Optional `direction` (default `down`) accepts `up`, '
              '`down`, `left`, `right`.\n'
              '- Optional `pixels` (default 300) tunes the scroll '
              'distance; pass larger values to page faster.\n'
              '- `dx` / `dy` (signed logical pixels) take precedence over '
              '`direction` / `pixels`; `intoView: true` brings `ref` itself '
              'into view instead.\n'
              '- Re-snap after the scroll completes; off-screen widgets '
              'gain refs only once Flutter builds them.\n'
              '- `scrolled` is true only when the offset moved. With no '
              'Scrollable around the ref, or one already at its edge, '
              '`scrolled` is false and `effect.changed` is false; read them '
              'before assuming the content moved.\n'
              '\n'
              'Example: `{ "ref": "e12", "direction": "down", "pixels": 500 }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (`e<N>`) inside the '
                    'target Scrollable. The extension walks up to the '
                    'nearest ancestor Scrollable.',
              },
              'direction': <String, dynamic>{
                'type': 'string',
                'enum': <String>['up', 'down', 'left', 'right'],
                'description': 'Scroll direction. Default `down`.',
              },
              'pixels': <String, dynamic>{
                'type': 'number',
                'description': 'Logical pixels to scroll. Default 300. '
                    'Larger values page faster but may overshoot.',
              },
              'dx': <String, dynamic>{
                'type': 'number',
                'description': 'Horizontal delta in logical pixels '
                    '(positive = right). Overrides `direction` / `pixels`.',
              },
              'dy': <String, dynamic>{
                'type': 'number',
                'description': 'Vertical delta in logical pixels '
                    '(positive = down). Overrides `direction` / `pixels`.',
              },
              'intoView': <String, dynamic>{
                'type': 'boolean',
                'description': 'Bring `ref` itself into view '
                    '(`Scrollable.ensureVisible`) instead of scrolling by a '
                    'delta.',
              },
              'snapshot': _kSnapshotProperty,
              'includeSnapshot': _kIncludeSnapshotProperty,
            },
            // No `required`: with no ref the handler scrolls the first
            // Scrollable it finds. tapir:scroll, the CLI, is the one that
            // insists on --ref.
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.scroll',
        ),
        // ---------------------------------------------------------------------
        // 8. Wait for: polls a condition until satisfied or the timeout
        // expires. One-of condition validated inside the handler.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_wait_for',
          description: 'Wait until a UI condition is satisfied or the timeout '
              'expires.\n'
              '\n'
              'Polls the running app at a fixed interval and returns once '
              'one of three one-of conditions is met: `text` (a Text with '
              'that data exists), `textGone` (no such Text exists), or '
              '`expression` (matched as text exactly like `text`; it is NOT '
              'evaluated as Dart, use tapir_evaluate for that). Useful for '
              'bridging async UI transitions before a follow-up tapir_tap / '
              'tapir_snap.\n'
              '\n'
              'Usage:\n'
              '- Pass ONE of `text`, `textGone`, `expression`; the handler '
              'errors when none is passed and, when several are, uses the '
              'first in that order.\n'
              '- Optional `timeoutMs` (default 5000) caps the wait. A '
              'timeout is a normal result, `{ matched: false, reason: '
              '"timeout" }`, not an error: check `matched` before going on. '
              'A match returns `{ matched: true, elapsedMs }`.\n'
              '- Polling interval is 200 ms; the handler returns as soon '
              'as the condition flips, never blocks the full timeout.\n'
              '\n'
              'Example: `{ "text": "Welcome", "timeoutMs": 3000 }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'text': <String, dynamic>{
                'type': 'string',
                'description': 'Wait until a Text widget with exactly this '
                    'data exists (an icon button\'s semantics label does not '
                    'count). One-of: pair with neither `textGone` nor '
                    '`expression`.',
              },
              'textGone': <String, dynamic>{
                'type': 'string',
                'description': 'Wait until no Text widget with exactly this '
                    'data exists. One-of: pair with neither `text` nor '
                    '`expression`.',
              },
              'expression': <String, dynamic>{
                'type': 'string',
                'description': 'Wait until a Text with this data exists '
                    '(matched as text, not evaluated as Dart). '
                    'One-of: pair with neither `text` nor `textGone`.',
              },
              'timeoutMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Wait timeout in milliseconds. Default '
                    '5000. On timeout the call returns an error, never '
                    'continues silently.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.wait_for',
        ),
        // ---------------------------------------------------------------------
        // 9. Dismiss modals: pops every dialog / bottom sheet / route on top
        // of the first persistent route.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_dismiss_modals',
          description: 'Pop every modal route (dialog, bottom sheet, popup) '
              'currently above the first persistent route.\n'
              '\n'
              'Walks the active Navigator stack and pops each modal route '
              'in LIFO order until only the first non-modal route remains. '
              'Useful for resetting the UI to a known state between test '
              'flows, dismissing left-over confirm dialogs, or clearing a '
              'stack of bottom sheets without per-modal taps.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- Idempotent: safe to call when no modals are open '
              '(returns immediately with zero pops).\n'
              '- Does NOT pop the root route; the underlying screen '
              'remains.\n'
              '- For dismissing a single specific dialog, prefer tapir_tap '
              'on the dialog\'s explicit Cancel button.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.dismiss_modals',
        ),
        // ---------------------------------------------------------------------
        // 10. Navigate: pushes a named route onto the active router.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_navigate',
          description: 'Navigate the running Flutter app to a route path.\n'
              '\n'
              'Pushes the supplied route onto the active router stack. '
              'Resolves through `MagicRoute.to(...)` when the Magic '
              'framework is installed, falling back to '
              '`Navigator.of(root).pushNamed(...)` otherwise. Useful for '
              'driving the app to a specific screen before taking a '
              'snapshot or action, without traversing the UI by hand.\n'
              '\n'
              'Usage:\n'
              '- Pass `route: "/monitors/123"` (must start with `/`).\n'
              '- ALWAYS re-snapshot after navigation; refs from a prior '
              'tapir_snap are invalidated by the route change.\n'
              '- `navigated: true` also covers a page under the route '
              '(`/monitors/7` for `/monitors`); `exactPath: true` says the '
              'Router shows the route itself.\n'
              '- For going back use tapir_navigate_back; to list known '
              'routes use tapir_get_routes.\n'
              '- `snapshot: "diff"` returns only the snapshot lines that '
              'changed since your last tapir_snap; `"none"` drops it.\n'
              '\n'
              'Example: `{ "route": "/login" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'route': <String, dynamic>{
                'type': 'string',
                'description': 'Route path to push. Must start with `/`. '
                    'Example: `/monitors/123`.',
              },
              'snapshot': <String, dynamic>{
                'type': 'string',
                'enum': <String>['full', 'diff', 'none'],
                'description': 'Post-navigate snapshot: the whole tree '
                    '(`full`, the default), only the changed lines (`diff`), '
                    'or none.',
              },
              'includeSnapshot': _kIncludeSnapshotProperty,
            },
            'required': <String>['route'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.navigate',
        ),
        // ---------------------------------------------------------------------
        // 11. Navigate back: pops the top route off the navigator stack.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_navigate_back',
          description: 'Pop the top route off the active navigator stack.\n'
              '\n'
              'Equivalent to pressing the system Back button: pops the '
              'outermost Navigator that has a page to leave, so a page '
              'stacked inside a shell (a go_router ShellRoute) is popped '
              'as well as one pushed on the root. Useful for returning '
              'from a detail screen to its list without snapshotting and '
              'tapping a Back AppBar button.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- No-op when the stack has only one route; safe to call '
              'speculatively.\n'
              '- Re-snapshot after the pop; refs from the previous screen '
              'are stale.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'snapshot': _kSnapshotProperty,
              'includeSnapshot': _kIncludeSnapshotProperty,
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.navigate_back',
        ),
        // ---------------------------------------------------------------------
        // 12. Get routes: where the app is right now.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_get_routes',
          description: 'Report where the running app is: the mounted '
              'Router\'s location, the top page\'s name and a title hint.\n'
              '\n'
              'Read it to confirm a tapir_navigate landed, or to see where a '
              'redirect took the app. It does not list the declared routes.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- Returns `{ location, title, uri }`. `uri` is the first '
              'mounted Router\'s location (`/monitors?page=2`), the value '
              'tapir_navigate verifies against; null while no Router is '
              'mounted, as on a loading screen right after a restart.\n'
              '- `location` is the root Navigator\'s top page name, which a '
              'Router-based app (go_router, MagicRouter) leaves empty on '
              'every screen; read `uri` there.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.get_routes',
        ),
        // ---------------------------------------------------------------------
        // 13. Press key: synthesises a hardware key event with optional
        // modifiers.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_press_key',
          description: 'Press a hardware key (optionally with modifiers).\n'
              '\n'
              'Delivers a `KeyDownEvent` + `KeyUpEvent` through the '
              "binding's `onKeyData`, the path real key data takes, so "
              'shortcut intents, `Focus.onKeyEvent` handlers, and '
              '`CallbackShortcuts` widgets fire. Use for keyboard-driven '
              'flows that have no equivalent tap target: Escape to close, '
              'Enter to submit, arrow keys to navigate a list, Ctrl+S to '
              'save.\n'
              '\n'
              'Usage:\n'
              '- Pass `key: "Enter"` (key name from '
              '`LogicalKeyboardKey.keyLabel`). Common values: `Enter`, '
              '`Escape`, `Tab`, `ArrowDown`, `Backspace`. A single '
              'letter or digit (`G`, `m`, `7`) presses the key that '
              'types it, for shortcuts bound to a letter.\n'
              '- Optional `modifiers: ["control", "shift"]` are held down '
              'before the key and released after it, so exact-match '
              'shortcuts such as Shift+Tab or Ctrl+S fire.\n'
              '- For text input prefer tapir_type; this tool is for '
              'shortcut keys only.\n'
              '\n'
              'Example: `{ "key": "S", "modifiers": ["control"] }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'key': <String, dynamic>{
                'type': 'string',
                'description': 'Logical key label, or one letter or '
                    'digit. Examples: `Enter`, `Escape`, `Tab`, '
                    '`ArrowDown`, `S`, `7`, `Backspace`.',
              },
              'modifiers': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{
                  'type': 'string',
                  'enum': <String>['control', 'shift', 'alt', 'meta'],
                },
                'description': 'Modifier keys held during the press. '
                    'Accepts any subset of `control`, `shift`, `alt`, '
                    '`meta`.',
              },
              'snapshot': _kSnapshotProperty,
              'includeSnapshot': _kIncludeSnapshotProperty,
            },
            'required': <String>['key'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.press_key',
        ),
        // ---------------------------------------------------------------------
        // 14. Select option: drives a DropdownButton / DropdownButtonFormField
        // to the matching item.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_select_option',
          description: 'Select an option in a DropdownButton by ref + value.\n'
              '\n'
              'Opens the `DropdownButton` / `DropdownButtonFormField` '
              'identified by `ref`, finds the item whose value equals '
              '`value`, and taps it. Bridges the gap between tapir_tap '
              '(which opens the menu) and a second tapir_snap+tapir_tap '
              'pair (which would otherwise be needed to pick the item).\n'
              '\n'
              'Usage:\n'
              '- Pass `ref` of the dropdown widget from a prior '
              'tapir_snap.\n'
              '- Pass `value` matching the option text or the underlying '
              'value (the handler tries label match first, then '
              '`toString()` of the underlying value).\n'
              '- Re-snap after the selection; the dropdown closes and '
              'downstream widgets may re-render.\n'
              '\n'
              'Example: `{ "ref": "e7", "value": "GET" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Dropdown widget ref token (`e<N>`) from '
                    'a prior tapir_snap.',
              },
              'value': <String, dynamic>{
                'type': 'string',
                'description': 'Option to select. Matches against the '
                    'displayed label first, then `toString()` of the '
                    'underlying value.',
              },
            },
            'required': <String>['ref', 'value'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.select_option',
        ),
        // ---------------------------------------------------------------------
        // 15. Evaluate: runs a Dart expression through the Tinker bridge.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_evaluate',
          description:
              'Evaluate a Dart expression in the running app isolate.\n'
              '\n'
              'Forwards `expression` to the Tinker bridge '
              '(`ext.tinker.evaluate`) and returns the stringified result. '
              'Useful for inspecting controller state, asserting an '
              'invariant from the model layer, or reading a private '
              'getter that has no UI surface. Reaches anything visible '
              'to the Magic facade autocomplete (Auth, Http, Cache, '
              'controllers via `Magic.find<T>()`).\n'
              '\n'
              'Usage:\n'
              '- Pass a single Dart expression (no statements, no '
              'semicolons). Example: `Magic.find<MonitorController>().'
              'rxState.value.length`.\n'
              '- Errors when the Tinker plugin is not installed (returns '
              'an MCP error result, never crashes the app).\n'
              '- For UI assertions prefer tapir_snap; this tool is for '
              'state inspection that lives below the Semantics tree.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'expression': <String, dynamic>{
                'type': 'string',
                'description': 'Single Dart expression to evaluate. No '
                    'statements; no trailing semicolon. Example: '
                    '`Auth.user?.email`.',
              },
            },
            'required': <String>['expression'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.evaluate',
        ),
        // ---------------------------------------------------------------------
        // 16. Close app: requests a graceful shutdown of the running app.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_close_app',
          description: 'Request a graceful shutdown of the running Flutter '
              'app.\n'
              '\n'
              'Calls `SystemNavigator.pop()` which routes through the '
              'platform back-button channel. On mobile + desktop this '
              'terminates the app; on web the call is a no-op (browsers '
              'do not allow programmatic tab close). Useful at the end '
              'of a long-running E2E session when the next test run '
              'wants a clean process.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- After calling this, the next tapir_* tool will fail '
              'because the VM Service URI is gone; restart the app '
              'before issuing further commands.\n'
              '- No-op on web; pair with manual tab close if you need a '
              'fresh browser session.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.close_app',
        ),
        // ---------------------------------------------------------------------
        // 17. Find: Playwright-Locator-style query handle. q-shape refs
        // re-execute the stored predicates on each action call.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_find',
          description:
              'Find a widget by semantic query (text / semanticsLabel / '
              'key) and return a re-resolvable handle.\n'
              '\n'
              'Mints a `q<N>` handle backed by the supplied predicates. '
              'Unlike `e<N>` refs from tapir_snap (which freeze the widget '
              'position at snap time and stale on rebuild), q-handles '
              're-execute the Semantics + Element tree walk on every '
              'subsequent tapir_tap / tapir_hover / tapir_drag / tapir_type '
              'call, so they survive widget rebuilds, route pushes, and '
              'snapshot disposal as long as the predicates still match.\n'
              '\n'
              'Usage:\n'
              '- Pass at least one of `text`, `semanticsLabel`, or `key`. '
              'When multiple are supplied they form an intersection.\n'
              '- Prefer tapir_find when the target survives re-renders '
              '(stable Text, stable accessibility label, stable Key); '
              'prefer tapir_snap+`eN` when you want a positional snapshot '
              'of the whole tree.\n'
              '- Returns `{ref: "q<N>", matched: true}` on first match, '
              'or `{ref: null, matched: false}` when no node matches.\n'
              '- When a follow-up action call finds zero live matches, '
              'the handler returns a "stale handle" error — agent must '
              're-find or re-snap, NOT retry.\n'
              '\n'
              'Example: `{ "text": "Submit" }` or `{ "key": "monitor-row-7" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'text': <String, dynamic>{
                'type': 'string',
                'description': 'Exact match against an accessibility label '
                    'first, then against `Text.data` as fallback. Example: '
                    '`"Submit"` matches a labelled button or a visible '
                    '`Text("Submit")` widget.',
              },
              'semanticsLabel': <String, dynamic>{
                'type': 'string',
                'description': 'Exact match against `SemanticsNode.label` '
                    'ONLY (no Text fallback). Use when the visible text '
                    'differs from the accessibility label.',
              },
              'key': <String, dynamic>{
                'type': 'string',
                'description': 'Match against a widget Key. For ValueKey, '
                    'pass the inner value\'s `toString()` (e.g. '
                    '`"monitor-row-7"`); for arbitrary Keys, pass the '
                    'full `Key.toString()` value.',
              },
              'within': <String, dynamic>{
                'type': 'string',
                'description': 'Evaluate the predicates inside one subtree: '
                    'the `e<N>` ref of the region to search. Reach for it '
                    'whenever a label repeats across the shell, which a '
                    'sidebar and the page it opens usually do, because the '
                    'unscoped match lands on the nav item. The scope is part '
                    'of the minted `q<N>` handle, so it survives into every '
                    're-resolve; once the scope stops resolving the handle '
                    'reports no match with a diagnostic naming it.',
              },
              'contains': <String, dynamic>{
                'type': 'string',
                'description': 'Substring of a semantics label or `Text` '
                    'data, for labels that carry dynamic parts. It is the '
                    'last predicate tried: a `key`, `semanticsLabel` or '
                    '`text` given with it decides the match.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.find',
        ),
        // ---------------------------------------------------------------------
        // 18. Wait for network idle (Step 3.4). Polls
        // CrumbsStore.pendingHttpCount via the pendingHttpCountReader
        // function-pointer indirection (set by the host when crumbs is
        // installed; defaults to () => 0 otherwise ; missing-crumbs
        // graceful path returns matched=true immediately).
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_wait_for_network_idle',
          description: 'Wait until the running app reports zero in-flight HTTP '
              'requests for a contiguous idleMs window.\n'
              '\n'
              'Polls the host\'s in-flight HTTP counter (wired by '
              'crumbs\'s `MagicHttpFacadeAdapter.pendingCount` '
              'when both packages are present) every `pollIntervalMs` ms. '
              'When the counter reaches 0 a continuous-zero countdown of '
              '`idleMs` starts; any spike back to a positive count fully '
              'resets the accumulator (Playwright `waitForLoadState` '
              'network-idle semantics). On success returns '
              '`{matched: true, idleAchievedMs: <int>}`; on timeout returns '
              'a structured error envelope with `type: "timeout"` and the '
              'max in-flight count observed inside the wire `message` field.\n'
              '\n'
              'Usage:\n'
              '- No required params; sensible defaults '
              '(`timeoutMs=5000`, `idleMs=500`, `pollIntervalMs=200`).\n'
              '- Call AFTER tapir_tap / tapir_navigate / tapir_select_option to '
              'bridge async network round-trips before a follow-up tapir_snap. '
              'Replaces the `tapir_wait_for textGone=Loading...` pattern when '
              'the loading affordance is not Semantically labelled.\n'
              '- Missing-crumbs graceful: when the host has not wired '
              'crumbs the counter is constantly 0 and the call returns '
              'idle immediately, so callers do not need to branch on the '
              'host\'s install state.\n'
              '- `pollIntervalMs` must be >= 100ms (CPU constraint); the '
              'handler asserts this internally.\n'
              '\n'
              'Example: `{ "timeoutMs": 8000, "idleMs": 750 }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'timeoutMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum total wait time in milliseconds. '
                    'Default 5000.',
              },
              'idleMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Contiguous-zero window the loop must observe '
                    'before declaring idle. Default 500.',
              },
              'pollIntervalMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Poll cadence in milliseconds. Minimum 100; '
                    'default 200.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.wait_for_network_idle',
        ),
        // ---------------------------------------------------------------------
        // 19. Console: reads recent log entries from the crumbs store.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_console',
          description: 'Read recent log entries from the running app\'s '
              'crumbs store.\n'
              '\n'
              'Reads structured log entries recorded by the crumbs HTTP '
              'adapter and log watcher when `crumbs` is '
              'installed and wired. When crumbs is absent the call '
              'returns an empty list immediately (missing-crumbs graceful '
              'path), so callers do not need to branch on install state.\n'
              '\n'
              'Usage:\n'
              '- No required params; defaults to the 50 most recent entries '
              'at any severity level.\n'
              '- Pass `limit: <n>` to cap the returned count.\n'
              '- Pass `minLevel: "WARNING"` (or `"ERROR"`) to filter by '
              'minimum severity level.\n'
              '- Each log entry contains `level`, `message`, `time`, and '
              '`logger` fields.\n'
              '- Useful for asserting that a controller logged an expected '
              'message without needing to inspect the UI tree.\n'
              '\n'
              'Example: `{ "limit": 10, "minLevel": "ERROR" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'limit': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum number of log entries to return. '
                    'Default 50.',
              },
              'minLevel': <String, dynamic>{
                'type': 'string',
                'description': 'Minimum severity level to include. Examples: '
                    '`INFO`, `WARNING`, `ERROR`. Omit to include all levels.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.console',
        ),
        // ---------------------------------------------------------------------
        // 20. Exceptions: reads recent exception entries from crumbs.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_exceptions',
          description: 'Read recent exceptions recorded by the running app, '
              'including non-fatal FlutterErrors.\n'
              '\n'
              'Returns the merged union of two sources: the in-package '
              'non-fatal `FlutterError.onError` capture buffer (installed '
              'by `TapirPlugin.install()`) and the crumbs exception '
              'watcher (when `crumbs` is present). Entries '
              'are deduped by `(type, message, stackHead)`, sorted '
              'newest-first, and clipped to `limit`. RenderFlex overflow '
              'errors appear with `type: "overflow"`. Missing-crumbs '
              'graceful: the in-package buffer alone ensures non-fatal '
              'errors are visible even without crumbs.\n'
              '\n'
              'Usage:\n'
              '- No required params; defaults to the 20 most recent exceptions.\n'
              '- Pass `limit: <n>` to cap the returned count.\n'
              '- Pass `since: "<iso8601>"` to return only exceptions strictly '
              'after that timestamp (e.g. capture the time before an action, '
              'then call with `since` to see only new exceptions).\n'
              '- Each entry contains `type`, `message`, `stackHead` (first '
              '3 lines of the stack trace), `library`, `fatal`, and `time`.\n'
              '- Useful for asserting that an action did not trigger an '
              'unexpected exception, or for diagnosing overflow errors '
              'flagged in a prior tapir_snap `overflow: true` annotation.\n'
              '\n'
              'Example: `{ "limit": 5, "since": "2024-01-01T10:00:00.000Z" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'limit': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum number of exception entries to '
                    'return. Default 20.',
              },
              'since': <String, dynamic>{
                'type': 'string',
                'description': 'ISO8601 timestamp. When set, only exceptions '
                    'whose `time` is strictly after this value are returned. '
                    'Omit to return the full cumulative list. Unparseable '
                    'values are silently ignored (treated as absent).',
              },
              'clear': <String, dynamic>{
                'type': 'boolean',
                'description': 'Empty the in-package capture buffer AFTER '
                    'returning the current entries. The buffer is cumulative, '
                    'so one real fault at boot rides along on every later '
                    'read and a per-route sweep reports it against every '
                    'route. Clear between routes to get a real delta. Only '
                    'the in-package buffer is affected; a wired crumbs '
                    'owns its own store.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.exceptions',
        ),
        // ---------------------------------------------------------------------
        // 21. Double-click: two tap sequences at ref center (~100ms apart).
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_dblclick',
          description: 'Double-click a widget by ref token from a prior '
              'tapir_snap.\n'
              '\n'
              'Synthesizes two pointer Down+50ms+Up sequences at the center '
              'of the widget identified by `ref`, with ~100ms between the '
              'two taps, matching Playwright\'s double-click model. Triggers '
              '`GestureDetector.onDoubleTap` and any double-tap handlers '
              'registered on that widget. The six-step actionability gate '
              '(defunct, enabled, zero rect, off-viewport, stable, receives '
              'events) runs before the '
              'first tap; the post-action snapshot is captured once after the '
              'second tap completes.\n'
              '\n'
              'Usage:\n'
              '- Call tapir_snap first to get a ref token; the ref string '
              'has shape `e<N>` or `q<N>`.\n'
              '- For single tap use tapir_tap; for drag use tapir_drag.\n'
              '- Returns the ref of the clicked widget on success; errors '
              'when the ref is unknown, stale, or the widget fails the '
              'actionability gate.\n'
              '\n'
              'Example: `{ "ref": "e7" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token from a prior tapir_snap '
                    'call. Shape: `e<N>` (e.g. `e5`, `e23`).',
              },
              'snapshot': _kSnapshotProperty,
              'includeSnapshot': _kIncludeSnapshotProperty,
              'checkStable': _kCheckStableProperty,
              'checkReceivesEvents': _kCheckReceivesEventsProperty,
            },
            'required': <String>['ref'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.dblclick',
        ),
        // ---------------------------------------------------------------------
        // 22. Set checkbox: read + conditionally toggle a Checkbox or Switch.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_set_checkbox',
          description: 'Set the checked state of a Checkbox or Switch widget '
              'by ref.\n'
              '\n'
              'Reads the widget\'s current checked state via an element/Semantics '
              'walk. When the current value already matches `value` the call '
              'returns an idempotent success without tapping (safe to call '
              'speculatively). When the current value differs, injects a tap '
              'at the widget\'s center to toggle it.\n'
              '\n'
              'Usage:\n'
              '- Call tapir_snap first to get a ref token for the target '
              'Checkbox or Switch widget.\n'
              '- Pass `value: "true"` to check or `value: "false"` to uncheck.\n'
              '- Returns `{ref, previousValue, value, toggled: bool}` — use '
              '`toggled` to confirm whether a tap was actually issued.\n'
              '- Re-snap after a toggle to see the updated Semantics tree.\n'
              '\n'
              'Example: `{ "ref": "e4", "value": "true" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Checkbox or Switch widget ref token (`e<N>`) '
                    'from a prior tapir_snap.',
              },
              'value': <String, dynamic>{
                'type': 'string',
                'enum': <String>['true', 'false'],
                'description': 'Target checked state. `"true"` checks the '
                    'widget; `"false"` unchecks it.',
              },
            },
            'required': <String>['ref', 'value'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.set_checkbox',
        ),
        // ---------------------------------------------------------------------
        // 23. Observe: structured candidate list (Stagehand observe-once-
        // act-many; no server-side LLM).
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_observe',
          description:
              'Return a structured candidate list of every interactive widget '
              'on screen.\n'
              '\n'
              'Walks the live Semantics + Element tree once, finds every '
              'interactive node (buttons, text fields, links, checkboxes, '
              'dropdowns — same role detection as tapir_find; a control merged '
              'into a MergeSemantics boundary is listed once), and mints a '
              're-resolvable `q<N>` ref for each candidate via the '
              'Playwright-Locator pattern. NO server-side LLM is invoked: '
              'the agent reads the candidate list and decides which refs to '
              'act on. Implements Stagehand\'s observe-once-act-many pattern.\n'
              '\n'
              'Each candidate carries: `ref`, `role`, `label`, `value`, '
              '`bounds` (x/y/w/h), `isEnabled`, `isVisible`, `inViewport`, '
              '`occluded` (covered from above), plus a subset '
              'of per-candidate enricher fields when '
              '`includeEnrichers=true` (default: `magicFormField`, '
              '`magicRoute`, `magicGateResult`, `wind.breakpoint`, '
              '`wind.states`).\n'
              '\n'
              'Usage:\n'
              '- No required params; sensible defaults observe every role '
              'with `limit=50` and the default enricher subset.\n'
              '- Pass `intent: "<hint>"` to record what the agent is looking '
              'for (NOT used server-side; accepted purely for caller-side '
              'audit logging).\n'
              '- Pass `roles: "button,textbox"` to filter the candidate '
              'list to a comma-separated subset.\n'
              '- Pass `limit: <n>` to cap the candidate count.\n'
              '- Pass `includeEnrichers: "false"` to skip enricher fields '
              'entirely; pass `includeEnrichers: "full"` for every enricher '
              'field (incl. full `wind` block).\n'
              '- q-refs survive widget rebuilds; reuse a single observe '
              'output across many follow-up tapir_tap / tapir_type / tapir_drag '
              'calls without re-observing.\n'
              '- Candidates sharing one label stay distinct: each handle '
              'carries its position among the nodes that label matched, so a '
              'list of rows offering one action is safe to act on row by row. '
              'A vanished row reports a stale handle; a row INSERTED above '
              'the list does not, and shifts every handle you hold, so '
              're-observe after anything that can prepend.\n'
              '\n'
              'Examples:\n'
              '- `{ "roles": "button", "limit": 20 }`\n'
              '- `{ "intent": "login form", "roles": "textbox,button" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'intent': <String, dynamic>{
                'type': 'string',
                'description': 'Free-form caller hint describing what the '
                    'agent is looking for (e.g. "login form"). NOT used '
                    'server-side; echoed in audit logs only.',
              },
              'roles': <String, dynamic>{
                'type': 'string',
                'description': 'Comma-separated role filter '
                    '(e.g. `"button,textbox"`). Roles match the same '
                    'vocabulary as tapir_snap: `button`, `textbox`, `link`, '
                    '`checkbox`, `heading`, `image`. Omit for every role.',
              },
              'limit': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum number of candidates to return. '
                    'Default 50.',
              },
              'includeEnrichers': <String, dynamic>{
                'type': 'string',
                'enum': <String>['true', 'false', 'full'],
                'description': 'Toggle per-candidate enricher fields. '
                    '`"true"` (default) projects the default subset '
                    '(magicFormField, magicRoute, magicGateResult, '
                    'wind.breakpoint+states); `"false"` projects no '
                    'enricher fields; `"full"` projects every field '
                    'including all wind sub-fields.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.observe',
        ),
        // ---------------------------------------------------------------------
        // 24. Hot reload and snap (Step 4.2): mcp_flutter's
        // fmt_hot_reload_and_capture pattern. Triggers a VM Service hot reload
        // from outside the running isolate (a same-isolate handler would block
        // on reloadSources against itself), then bundles snapshot + screenshot
        // + recent exceptions into one response.
        //
        // extensionMethod routes through the `dowel:` substrate dispatch
        // prefix instead of `ext.tapir.*`; the MCP server executes the CLI
        // command (`tapir:hot_reload_and_snap`) in-process so the orchestration
        // can drive `vm.reloadSources` against the target isolate.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_hot_reload_and_snap',
          description: 'Hot reload the running Flutter app, then capture a '
              'snapshot, screenshot, and recent exceptions in one '
              'round-trip.\n'
              '\n'
              'Triggers `reloadSources` over the VM Service against the '
              'running app, waits for completion, then calls tapir_snap + '
              'tapir_screenshot + tapir_exceptions and bundles every result '
              'into a single response. Equivalent to mcp_flutter\'s '
              '`fmt_hot_reload_and_capture`; saves three round-trips when '
              'the agent needs to validate that a code change took effect.\n'
              '\n'
              'Usage:\n'
              '- No required params; sensible defaults capture the '
              'screenshot.\n'
              '- Pass `screenshot: "false"` to skip the screenshot step '
              '(useful when the agent only needs the Semantics tree).\n'
              '- On reload success the response carries `reloaded: true`, '
              '`durationMs`, `snapshot`, `screenshot` (or `screenshotError` '
              'when capture failed; the snapshot still lands), and '
              '`recentExceptions`.\n'
              '- On compile error the response carries `reloaded: false`, '
              '`durationMs`, `error` (the compile message), and '
              '`recentExceptions`. snapshot + screenshot are omitted, and the '
              'call returns as an error result.\n'
              '- Recent exceptions reuse tapir_exceptions wiring; missing '
              'crumbs is graceful (empty list).\n'
              '\n'
              'Example: `{ "screenshot": "false" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'screenshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Capture a screenshot after the reload '
                    '(default true). Pass `false` to skip the screenshot '
                    'step.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'dowel:tapir:hot_reload_and_snap',
        ),
        // -------------------------------------------------------------------
        // P4 (Playwright parity): focus / blur / clear / right_click /
        // triple_click. Five short descriptors; the behavior mirrors the
        // matching Playwright Locator methods (focus, blur, clear,
        // click({button:right}), click({clickCount:3})).
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_focus',
          description: 'Request keyboard focus on the widget identified by '
              '`ref`.\n\n'
              'Playwright parity: `locator.focus()`. Walks the resolved '
              'element to find the nearest Focus ancestor and calls '
              'requestFocus(). Returns `{ref, focused: true}`.\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref token from a prior tapir_snap.\n'
              '- `includeSnapshot` (default false): embed post-focus snapshot.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-focus snapshot (default false).',
              },
            },
            'required': <String>['ref'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.focus',
        ),
        McpToolDescriptor(
          name: 'tapir_blur',
          description: 'Clear keyboard focus from whatever currently holds it.'
              '\n\n'
              'Playwright parity: `locator.blur()` / `document.activeElement'
              '.blur()`. Returns `{blurred: true, hadFocus: bool}`.\n\n'
              'Usage:\n'
              '- No required params; blurs the primary focused node.\n'
              '- `includeSnapshot` (default false): embed post-blur snapshot.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-blur snapshot (default false).',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.blur',
        ),
        McpToolDescriptor(
          name: 'tapir_clear',
          description: 'Empty the TextEditingController backing the resolved '
              'text field.\n\n'
              'Playwright parity: `locator.clear()`. Walks the resolved '
              'element to find an EditableText descendant, extracts its '
              'controller, calls clear(). Returns `{ref, text: ""}`.\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref of a TextField / TextFormField '
              '/ EditableText.\n'
              '- `includeSnapshot` (default false): embed post-clear snapshot.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref of the text field (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-clear snapshot (default false).',
              },
            },
            'required': <String>['ref'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.clear',
        ),
        McpToolDescriptor(
          name: 'tapir_right_click',
          description: 'Fire a right (secondary mouse button) click at the '
              'widget identified by `ref`.\n\n'
              'Playwright parity: `locator.click({ button: "right" })`. '
              'Useful for context menus. Runs the six-step actionability gate '
              'before injecting the PointerDownEvent + 50ms hold + '
              'PointerUpEvent (mouse kind, kSecondaryButton).\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref token.\n'
              '- `includeSnapshot` (default true): embed post-action snapshot.\n'
              '- `checkStable`/`checkReceivesEvents` (both default true): '
              'gate opt-outs.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-action snapshot (default true).',
              },
              'checkStable': <String, dynamic>{
                'type': 'boolean',
                'description':
                    'Run the Stable actionability gate (default true).',
              },
              'checkReceivesEvents': <String, dynamic>{
                'type': 'boolean',
                'description': 'Run the Receives-Events actionability gate '
                    '(default true).',
              },
              'snapshot': _kSnapshotProperty,
            },
            'required': <String>['ref'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.right_click',
        ),
        McpToolDescriptor(
          name: 'tapir_triple_click',
          description: 'Fire three primary clicks (~100ms apart) at the '
              'widget identified by `ref`.\n\n'
              'Playwright parity: `locator.click({ clickCount: 3 })`. In '
              'Material text fields this selects an entire paragraph. Runs '
              'the six-step actionability gate once before the first tap; '
              'subsequent taps assume the target is still actionable.\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref token.\n'
              '- `includeSnapshot` (default true): embed post-action snapshot.\n'
              '- `checkStable`/`checkReceivesEvents` (both default true): '
              'gate opt-outs.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-action snapshot (default true).',
              },
              'checkStable': <String, dynamic>{
                'type': 'boolean',
                'description':
                    'Run the Stable actionability gate (default true).',
              },
              'checkReceivesEvents': <String, dynamic>{
                'type': 'boolean',
                'description': 'Run the Receives-Events actionability gate '
                    '(default true).',
              },
              'snapshot': _kSnapshotProperty,
            },
            'required': <String>['ref'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.triple_click',
        ),
        // -------------------------------------------------------------------
        // 25. Resize viewport: set dimensions, DPR, mobile, touch via CDP.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_resize_viewport',
          description: 'Resize the running Flutter web app viewport via Chrome '
              'DevTools Protocol.\n'
              '\n'
              'Sets browser viewport dimensions, device pixel ratio, mobile '
              'profile, and touch emulation flags via the Emulation.* CDP '
              'methods. Allows testing responsive layouts and mobile-only UI '
              'without DevTools manual intervention. Requires dowel to have '
              'been started with --cdp-port (which pre-launches Chrome with a '
              'debug port); fail-loudly if cdpPort is not set.\n'
              '\n'
              'The override lasts only as long as the CDP session this call '
              'opens, and the call closes that session when it returns: '
              'Chrome then drops the override, so a later snapshot or '
              'screenshot sees the page at its own size. This tool cannot '
              'keep it; the CLI `tapir:resize --hold`, run in the background, '
              'holds the session and so the override while you drive the '
              'app.\n'
              '\n'
              'Usage:\n'
              '- A resize needs `width` (integer, CSS pixels; e.g. 375 for '
              'iPhone) and `height` (integer, CSS pixels; e.g. 812); only '
              '`reset` goes without them.\n'
              '- Optional `dpr` (number; default 1.0) simulates device pixel '
              'ratio. Use 2.0 for Retina, 3.0 for iPhone Pro.\n'
              '- Optional `mobile` (boolean; default false) enables mobile '
              'device profile (affects text sizing, viewport meta, scrolling '
              'UX).\n'
              '- Optional `touch` (boolean; default false) enables touch event '
              'synthesis (PointerDown/Move/Up sequences).\n'
              '- Optional `reset` (boolean; default false) clears ALL viewport '
              'overrides (metrics, touch, user agent) in one call. When true, '
              'all other params are ignored.\n'
              '\n'
              'Examples:\n'
              '- `{"width": 375, "height": 812, "dpr": 3.0, '
              '"mobile": true, "touch": true}` (iPhone-X emulation).\n'
              '- `{"width": 1440, "height": 900, "reset": false}` (desktop '
              'viewport).\n'
              '- `{"reset": true}` (clear overrides, revert to host defaults).',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'width': <String, dynamic>{
                'type': 'integer',
                'description': 'Viewport width in CSS pixels (required '
                    'unless `reset`). Example: 375 for mobile, 1440 for '
                    'desktop.',
              },
              'height': <String, dynamic>{
                'type': 'integer',
                'description': 'Viewport height in CSS pixels (required '
                    'unless `reset`). Example: 812 for mobile, 900 for '
                    'desktop.',
              },
              'dpr': <String, dynamic>{
                'type': 'number',
                'description': 'Device pixel ratio (optional; default 1.0). '
                    'Use 2.0 for Retina, 3.0 for iPhone Pro DPR. Must be '
                    'greater than 0.',
              },
              'mobile': <String, dynamic>{
                'type': 'boolean',
                'description': 'Enable mobile device profile (optional; default '
                    'false). Affects viewport meta tag behavior, text autosizing, '
                    'and scrolling UX.',
              },
              'touch': <String, dynamic>{
                'type': 'boolean',
                'description': 'Enable touch event synthesis (optional; default '
                    'false). When true, browser fires touch events instead of '
                    'mouse events.',
              },
              'reset': <String, dynamic>{
                'type': 'boolean',
                'description': 'Clear all viewport overrides (optional; default '
                    'false). When true, metrics + touch + user agent are reset. '
                    'All other params ignored when reset is true.',
              },
            },
            // No `required`: `{"reset": true}` names no size, and dowel
            // refuses a call that lacks a required key before the command
            // runs. TapirResizeCommand refuses a resize without a size.
            'additionalProperties': false,
          },
          extensionMethod: 'dowel:tapir:resize',
        ),
        // -------------------------------------------------------------------
        // 26. Device profile: emulate a named device preset via CDP.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_device_profile',
          description: 'Emulate a named device profile (viewport + DPR + touch '
              '+ user agent) via Chrome DevTools Protocol.\n'
              '\n'
              'Applies a curated device preset (iphone-x, pixel-5, ipad-pro, '
              'desktop-1440, etc.) in a single call. Each preset bundles the '
              'correct viewport dimensions, device pixel ratio, touch '
              'emulation flag, and user agent string so the app renders as it '
              'would on that actual device. Requires dowel to have been '
              'started with --cdp-port (which pre-launches Chrome with a debug '
              'port).\n'
              '\n'
              'The emulated viewport, DPR, touch and user agent last only as '
              'long as the CDP session this call opens, which closes when it '
              'returns; only the Chrome window size it sets stays. For a '
              'viewport that lasts, run the CLI `tapir:resize --hold` in the '
              'background.\n'
              '\n'
              'Usage:\n'
              '- Call with `list: true` (no `preset` required) to enumerate '
              'all available device presets with dimensions.\n'
              '- Call with `preset: "<name>"` (string; no list) to apply a '
              'preset. Valid preset names: iphone-x, iphone-13, iphone-15-pro, '
              'pixel-5, pixel-8, ipad-pro-12.9, desktop-1440, desktop-1920.\n'
              '- Call with `reset: true` (optional; no preset required) to '
              'clear all overrides (metrics, touch, user agent). Equivalent to '
              'tapir_resize_viewport with reset=true.\n'
              '- When `preset` is unknown, exits with error and suggests '
              'running with `list: true` to see available options.\n'
              '\n'
              'Examples:\n'
              '- `{"preset": "iphone-x"}` (apply iPhone-X emulation).\n'
              '- `{"list": true}` (show all 8 presets).\n'
              '- `{"reset": true}` (clear overrides).',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'preset': <String, dynamic>{
                'type': 'string',
                'enum': <String>[
                  'iphone-x',
                  'iphone-13',
                  'iphone-15-pro',
                  'pixel-5',
                  'pixel-8',
                  'ipad-pro-12.9',
                  'desktop-1440',
                  'desktop-1920',
                ],
                'description': 'Device preset name (optional). One of: '
                    'iphone-x, iphone-13, iphone-15-pro, pixel-5, pixel-8, '
                    'ipad-pro-12.9, desktop-1440, desktop-1920. Omit when '
                    'using list or reset.',
              },
              'list': <String, dynamic>{
                'type': 'boolean',
                'description': 'List all available device presets (optional; '
                    'default false). When true, preset and reset are ignored.',
              },
              'reset': <String, dynamic>{
                'type': 'boolean',
                'description': 'Clear all viewport overrides (optional; default '
                    'false). When true, metrics + touch + user agent are reset. '
                    'Preset is ignored when reset is true.',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'dowel:tapir:device',
        ),
        // -------------------------------------------------------------------
        // 27. Fill (D7): focus + clear + type + settle + stale-retry in one
        // call. Composes the gated focus / clear / type handlers.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_fill',
          description: 'Fill a text field by ref: focus, clear, type, settle '
              'in one call.\n'
              '\n'
              'Replaces the manual focus + clear + type + wait dance every '
              'agent otherwise re-discovers. Composes the gated focus, clear, '
              'and type handlers (so the actionability gate, IME focus, and '
              '`onChanged`/validator firing all run) and retries the whole '
              'sequence once when the ref goes stale mid-fill. Use after a '
              'tapir_snap (or tapir_find for a re-resolvable q-handle) to enter '
              'text without three separate round-trips.\n'
              '\n'
              'Usage:\n'
              '- Pass `ref` of the target TextField (`e<N>` or `q<N>`) and '
              '`text` to set. Pass `text: ""` to clear the field.\n'
              '- Prefer a q-handle (tapir_find) when the field may rebuild '
              'between snapshot and fill; the stale-retry then re-resolves '
              'cleanly on the second pass.\n'
              '- Returns `{ref, text, filled: true}` plus an optional '
              'post-fill snapshot.\n'
              '- `snapshot: "diff"` returns only the snapshot lines the fill '
              'changed since your last tapir_snap; `"none"` drops it. It '
              'overrides `includeSnapshot`.\n'
              '\n'
              'Example: `{ "ref": "e7", "text": "alice@example.com" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Text-field ref token (`e<N>` or `q<N>`) from '
                    'a prior tapir_snap / tapir_find.',
              },
              'text': <String, dynamic>{
                'type': 'string',
                'description': 'Value to set. Replaces existing content. Pass '
                    'an empty string to clear the field.',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-fill snapshot (default true).',
              },
              'snapshot': <String, dynamic>{
                'type': 'string',
                'enum': <String>['full', 'diff', 'none'],
                'description': 'Post-fill snapshot: the whole tree (`full`), '
                    'only the changed lines (`diff`), or none. Overrides '
                    '`includeSnapshot`.',
              },
              'checkStable': _kCheckStableProperty,
              'checkReceivesEvents': _kCheckReceivesEventsProperty,
            },
            'required': <String>['ref', 'text'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.fill',
        ),
        // -------------------------------------------------------------------
        // 28. Reset overlays (D7): dismiss + Escape + Cancel-tap fallback.
        // Idempotent; promotes the manual overlay-reset dance.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_reset_overlays',
          description: 'Reset the app to a clean screen: dismiss every modal, '
              'press Escape, then tap a Cancel/Dismiss affordance.\n'
              '\n'
              'Three escalating layers run in order, each a no-op when the '
              'prior already cleared the overlays: (1) pop every PopupRoute '
              '(dialogs, bottom sheets, popups) without touching the page '
              'stack; (2) an Escape key press for overlays driven by the '
              'dismiss shortcut; (3) a Cancel/Dismiss/Close/OK/Done labelled '
              'tap for modal barriers that need an explicit affordance. '
              'Idempotent: safe to call speculatively between flows.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- Returns `{popped: N, escaped: bool, dismissTapped: bool}` so '
              'you can see which layer cleared the screen.\n'
              '- Prefer this over tapir_dismiss_modals when an overlay is not '
              'a PopupRoute (custom OverlayEntry, dropdown menu, barrier '
              'dialog).',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.reset_overlays',
        ),
        // -------------------------------------------------------------------
        // 29. Perf begin: open a measurement session.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_perf_begin',
          description: 'Open a performance measurement session around an '
              'interaction you are about to drive.\n'
              '\n'
              'Zeroes the frame buffer and the wind and magic counters and '
              'records the liveness baseline the report is judged against. '
              'In attribution mode it also switches Flutter\'s build '
              'profiling on, which costs real time, so keep the session '
              'tight: begin, drive one interaction, end. Pair every call with '
              'tapir_perf_end, which puts every flag back.\n'
              '\n'
              'Usage:\n'
              '- Call with no params for attribution: blocks by self time, '
              'counts per painted frame, wind and magic counters, insights.\n'
              '- Set mode="timing" for a pass whose milliseconds are worth '
              'comparing: no profiling flag is touched and the report carries '
              'frame timings only.\n'
              '- Set phases=true (attribution only) to also profile layout '
              'and paint when builds alone did not explain the cost.\n'
              '- Returns `{sessionToken, mode, phases, livenessBaseline, '
              'restartedPreviousSession}`. A begin on an already-open session '
              'restarts it rather than failing.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'mode': <String, dynamic>{
                'type': 'string',
                'enum': <String>['attribution', 'timing'],
                'description': 'attribution (default) profiles builds; '
                    'timing touches no profiling flag and reports frame '
                    'timings only.',
              },
              'phases': <String, dynamic>{
                'type': 'boolean',
                'description': 'Also profile layout and paint, not just '
                    'builds (optional; default false; attribution only).',
              },
            },
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.perf_begin',
        ),
        // -------------------------------------------------------------------
        // 30. Perf end: close the session and report, or refuse.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_perf_end',
          description: 'Close the performance session and read a bounded '
              'report with ranked insights.\n'
              '\n'
              'Returns `{sessionToken, refused, mode, env, coverage, summary, '
              'counters, insights, omitted}`, about 6 KB at most. Every '
              'duration is in ms and every count is given raw and per '
              'painted frame. `summary` carries frame percentiles against a '
              'stated budgetMs of 16.7, dropped frames, and blocks ranked by '
              'SELF time and by count per painted frame. `insights` are '
              'sorted by severity then estimatedSavingsMs; each has an id, '
              'severity, title, evidence {metric, value, perFrame, threshold} '
              'and nextStep. Restores every profiling flag.\n'
              '\n'
              'Usage:\n'
              '- No parameters. Requires a prior tapir_perf_begin.\n'
              '- Check `refused` FIRST. When the liveness counter advanced by '
              '1 or less the engine rendered nothing, the response carries no '
              'metrics, and a zero report would have read as "fast". A '
              'backgrounded browser tab (web) or a hidden desktop window is '
              'the usual cause; the perf verbs do not force frames, so bring '
              'the window to front yourself.\n'
              '- Read `coverage.complete` and `coverage.missing` before the '
              'numbers: a subset or a missing source is not "nothing slow".\n'
              '- Call tapir_perf_insight with an insight id for the rows '
              'behind it; `omitted` counts what the report cut.\n'
              '- Attribution milliseconds are inflated by the profiling; '
              'compare milliseconds only across mode="timing" sessions.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.perf_end',
        ),
        // -------------------------------------------------------------------
        // 31. Perf insight: drill into one insight of the last report.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_perf_insight',
          description: 'Drill into one insight of the report tapir_perf_end '
              'last returned.\n'
              '\n'
              'Returns `{sessionToken, id, severity, title, summary, detail, '
              'estimatedSavingsMs, nextStep}`. `detail` holds the raw rows '
              'behind the insight: the worst frames with their self-time '
              'blocks, the frame-number gaps, the frames where a block '
              'weighed most, or what a coverage gap left out. Only the most '
              'recent closed session is kept.\n'
              '\n'
              'Usage:\n'
              '- Pass id="I2" from the insights[] list of tapir_perf_end. Ids '
              'are assigned before the list is cut, so one counted in '
              'omitted.insights is drillable too.\n'
              '- Pass token (the report\'s sessionToken) to guard against '
              'reading a newer session than the report you hold.\n'
              '- An unknown id, a stale token or a refused session returns an '
              'error naming what to read instead.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'id': <String, dynamic>{
                'type': 'string',
                'description': 'Insight id (I<n>) from tapir_perf_end.',
              },
              'token': <String, dynamic>{
                'type': 'string',
                'description': 'sessionToken of that report (optional).',
              },
            },
            'required': <String>['id'],
            'additionalProperties': false,
          },
          extensionMethod: 'ext.tapir.perf_insight',
        ),
        // -------------------------------------------------------------------
        // 32. Perf run: a scenario, repeated from a clean start, to a file.
        //
        // Routes through the `dowel:` substrate: the run restarts the app,
        // drives Chrome DevTools and writes files, none of which an in-isolate
        // extension can do.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_perf_run',
          description: 'Run a perf scenario YAML several times from a clean '
              'start and write medians, spread and insights to a file.\n'
              '\n'
              'Each repeat runs the scenario setup (its hot_restart, or a '
              'relaunch on a profile build), then perf_begin, the steps with '
              'targets resolved on the live screen, and perf_end. Writes '
              '<out>/<scenario>-<label>.json with env (host, renderer, '
              'restartMode), summary (medians of counts per painted frame and '
              'ms, plus a spread block), the median repeat\'s insights and '
              'every repeat. A refused repeat is recorded and left out of the '
              'medians; the call fails only when every repeat refused.\n'
              '\n'
              'Usage:\n'
              '- Pass scenario (a path) and a label ([a-z0-9_-]).\n'
              '- Pass variant when the file declares variants (required '
              'then, refused otherwise); it applies to against too.\n'
              '- Pass json=true for the summary as JSON (repeats stay in the '
              'file).\n'
              '- Set timing=true for interleaved timing-mode repeats, the only '
              'ms tapir_perf_compare gates on.\n'
              '- Set against to a baseline scenario path to run both in the '
              'same rounds, order alternating, one file each.\n'
              '- Set semantics-pass=true to also replay the steps by '
              'coordinates with the semantics tree released for the timed '
              'window (the semanticsOff series; unsupported for fill, type, '
              'scroll, and wherever a release leaves semantics on, which on '
              'chrome is every app tapir has snapshotted).\n'
              '- Chrome needs the app started with a CDP port.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'scenario': <String, dynamic>{
                'type': 'string',
                'description': 'Path to the scenario YAML.',
              },
              'variant': <String, dynamic>{
                'type': 'string',
                'description': 'The variants key to run; required when the '
                    'file declares variants.',
              },
              'label': <String, dynamic>{
                'type': 'string',
                'description': 'Run label in the file name, [a-z0-9_-] '
                    '(default run).',
              },
              'out': <String, dynamic>{
                'type': 'string',
                'description': 'Output directory (default build/perf).',
              },
              'repeat': <String, dynamic>{
                'type': 'integer',
                'description': 'Repeats per series; overrides the '
                    'scenario\'s repeat.',
              },
              'platform': <String, dynamic>{
                'type': 'string',
                'enum': <String>['chrome', 'android', 'ios'],
                'description': 'Target platform; read from the session when '
                    'omitted.',
              },
              'timing': <String, dynamic>{
                'type': 'boolean',
                'description': 'Also run interleaved timing-mode repeats.',
              },
              'against': <String, dynamic>{
                'type': 'string',
                'description': 'Baseline scenario YAML run in the same '
                    'rounds.',
              },
              'semantics-pass': <String, dynamic>{
                'type': 'boolean',
                'description': 'Also measure with the semantics tree '
                    'released.',
              },
              'json': <String, dynamic>{
                'type': 'boolean',
                'description': 'Print the summary as JSON.',
              },
            },
            'required': <String>['scenario'],
            'additionalProperties': false,
          },
          extensionMethod: 'dowel:tapir:perf_run',
        ),
        // -------------------------------------------------------------------
        // 33. Perf compare: judge run B against run A. Reads two files.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_perf_compare',
          description: 'Compare two tapir_perf_run files and return a verdict '
              'per metric.\n'
              '\n'
              'Gates on counts per painted frame, never on raw counts: a run '
              'that drew 10% fewer frames reports 10% fewer of everything '
              'and is not faster. Milliseconds are gated only from '
              'timing-mode medians; emulator raster ms are info only. A '
              'change inside the repeats\' own spread is unchanged. Default '
              'thresholds are warn +10% and error +25%, overridden by the '
              'scenario\'s thresholds. Returns {verdict, thresholds, frames, '
              'rows, unchanged, timing}; rows list only what changed.\n'
              '\n'
              'Usage:\n'
              '- Pass a (the baseline file) and b (the candidate file).\n'
              '- Pass json=true for the JSON; the default is a compact '
              'table.\n'
              '- The call fails on an error-level regression, or when either '
              'run has no measured repeat.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'a': <String, dynamic>{
                'type': 'string',
                'description': 'Baseline tapir_perf_run file.',
              },
              'b': <String, dynamic>{
                'type': 'string',
                'description': 'Candidate tapir_perf_run file.',
              },
              'json': <String, dynamic>{
                'type': 'boolean',
                'description': 'Return the result as JSON.',
              },
            },
            'required': <String>['a', 'b'],
            'additionalProperties': false,
          },
          extensionMethod: 'dowel:tapir:perf_compare',
        ),
        // -------------------------------------------------------------------
        // 34. Perf trace: the last closed session as a Chrome Trace file.
        //
        // Through the substrate so the trace, often thousands of events,
        // goes to a file and only its path comes back.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_perf_trace',
          description: 'Write the last closed perf session as a Chrome Trace '
              'JSON file and return only its path.\n'
              '\n'
              'Exports ext.tapir.perf_trace: interactions, frames and host rows '
              '(HTTP, events) of the session window, which ui.perfetto.dev '
              'and chrome://tracing open as is. The trace is too large for a '
              'context window, so it is written to out.\n'
              '\n'
              'Usage:\n'
              '- Pass out, the file to write.\n'
              '- Pass token (the report\'s sessionToken) to guard against a '
              'newer session.\n'
              '- Export before the next tapir_perf_begin, which clears the '
              'frames the trace reads.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'out': <String, dynamic>{
                'type': 'string',
                'description': 'File to write.',
              },
              'token': <String, dynamic>{
                'type': 'string',
                'description': 'sessionToken of the session (optional).',
              },
            },
            'required': <String>['out'],
            'additionalProperties': false,
          },
          extensionMethod: 'dowel:tapir:perf_trace',
        ),
        // -------------------------------------------------------------------
        // 35. Run: a batch of verb lines in one call.
        //
        // Through the substrate because the batch dispatches each step's CLI
        // command in-process on the server's one VM Service connection.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'tapir_run',
          description: 'Run several tapir verbs against the running app in '
              'one call.\n'
              '\n'
              'Each step is a CLI verb line without the `tapir:` prefix, '
              'tokenised like a shell (quotes and backslash escapes), and '
              'takes the same options as the standalone command. The '
              'response carries one line per step (`[1/3] tap --ref=e5 ok: '
              '<first output line>`), then the last step\'s full output. '
              'Saves a round trip per step when the next refs are already '
              'known.\n'
              '\n'
              'Usage:\n'
              '- Pass steps, e.g. `["tap --ref=e5", "fill --ref=q1 '
              '--text=\\"a b\\"", "snap --grep Total"]`.\n'
              '- The batch stops at the first failing step and returns '
              '`step N failed (exit C)` with that step\'s output; pass '
              '`continue: true` to run every step and report the first '
              'failure.\n'
              '- A step cannot be another run, nor a verb that does not run '
              'on the connected app (resize, device, install, doctor, '
              'perf_campaign, perf_compare); a step that ends the app '
              '(close_app, perf_run) must come last.\n'
              '- Refs minted by a snap inside the batch are not known before '
              'the call; end the batch with snap and read them from the '
              'output.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'steps': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{
                  'type': 'string',
                },
                'description': 'Verb lines, run in order (e.g. '
                    '`"tap --ref=e5"`).',
              },
              'continue': <String, dynamic>{
                'type': 'boolean',
                'description': 'Keep running after a failing step '
                    '(default false).',
              },
            },
            'required': <String>['steps'],
            'additionalProperties': false,
          },
          extensionMethod: 'dowel:tapir:run',
        ),
      ];
}
