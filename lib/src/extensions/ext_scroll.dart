import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'package:fluttersdk_artisan/artisan.dart';

import '../ref_registry.dart';
import '../utils/error_envelope.dart';
import 'ext_find.dart' show resolveQuery;
import 'ext_snapshot.dart' show duskSnapBuild;

/// Parses the optional `'true' | 'false'` flag [params] field [name],
/// returning [defaultValue] when missing or empty.
bool _parseBoolFlag(
  Map<String, String> params,
  String name, {
  required bool defaultValue,
}) {
  final String? raw = params[name];
  if (raw == null || raw.isEmpty) return defaultValue;
  return raw != 'false' && raw != '0';
}

/// Builds the post-action snapshot YAML and appends it under the
/// `snapshot` key of [payload], unless [params] sets
/// `includeSnapshot: 'false'`.
Future<void> _appendSnapshotIfRequested(
  Map<String, dynamic> payload,
  Map<String, String> params,
) async {
  if (!_parseBoolFlag(params, 'includeSnapshot', defaultValue: true)) {
    return;
  }
  final Map<String, dynamic> snap = await duskSnapBuild();
  payload['snapshot'] = snap['snapshot'];
}

/// Registers the `ext.dusk.scroll` and `ext.dusk.select_option` VM Service
/// extensions.
///
/// Call this once from the Wave 3 aggregator (`registerAllAiTestExtensions()`
/// in `extensions.dart`). Each call is idempotent via
/// [registerExtensionIdempotent], so hot-restart is safe.
void registerScrollExtensions() {
  registerExtensionIdempotent('ext.dusk.scroll', aiTestScrollHandler);
  registerExtensionIdempotent(
    'ext.dusk.select_option',
    aiTestSelectOptionHandler,
  );
}

// -----------------------------------------------------------------------------
// ext.dusk.scroll
// -----------------------------------------------------------------------------

/// Handler for the `ext.dusk.scroll` VM Service extension.
///
/// Params:
/// - `ref` (optional): RefRegistry key (`eN`) identifying the target element.
///   When supplied and `intoView=true`, the element is scrolled into view via
///   [Scrollable.ensureVisible]. When supplied without `intoView`, the nearest
///   parent scrollable of that element is scrolled by `dy`/`dx`.
/// - `dy` (optional): vertical delta in logical pixels (positive = down).
/// - `dx` (optional): horizontal delta in logical pixels (positive = right).
/// - `intoView` (optional, default `false`): when `true`, calls
///   [Scrollable.ensureVisible] on the resolved element with `alignment: 0.5`
///   and a 300 ms duration. Requires `ref` to identify the target element.
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-scroll accessibility snapshot in the response.
///
/// Returns `{ scrolled: true, finalOffset: <pixels>, snapshot: '<yaml>' }`
/// on success (snapshot key absent when `includeSnapshot: 'false'`), or an
/// extension error response on failure.
///
/// Must NOT use [PointerScrollEvent] (mouse-only; would not work on touch or
/// programmatic scroll).
Future<developer.ServiceExtensionResponse> aiTestScrollHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Parse parameters.
    final String? ref = params['ref'];
    final double dy = double.tryParse(params['dy'] ?? '') ?? 0.0;
    final double dx = double.tryParse(params['dx'] ?? '') ?? 0.0;
    final bool intoView =
        params['intoView'] == 'true' || params['intoView'] == '1';

    // 2. Resolve the target element. When a ref is provided, delegate to
    //    RefRegistry (landed in Step 6). When no ref is provided, search the
    //    widget tree for the first ScrollableState.
    BuildContext? targetContext;
    if (ref != null) {
      targetContext = _resolveRefContext(ref);
    }

    // 3. Perform the scroll operation.
    double finalOffset = 0.0;

    if (intoView && targetContext != null) {
      // Scroll into view — ensureVisible handles the math.
      await aiTestScrollEnsureVisible(
        targetContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
      );
      // Derive final offset from the parent scrollable after settling.
      // Element-bound BuildContext from RefRegistry stays valid across
      // ensureVisible's await — the registered element is not unmounted
      // mid-scroll in any production path.
      if (targetContext.mounted) {
        final ScrollableState? scrollable = Scrollable.maybeOf(targetContext);
        finalOffset = scrollable?.position.pixels ?? 0.0;
      }
    } else {
      // Scroll by delta — resolve the Scrollable in 3 stages so passing the
      // Scrollable's own ref (e.g. find --key=my-list returning the ListView
      // itself) works alongside the original "ref points at a descendant"
      // contract:
      // 1. Target element IS a Scrollable — use its state directly.
      // 2. Target has a Scrollable ancestor — Scrollable.maybeOf (legacy).
      // 3. Target wraps a Scrollable descendant — walk down to first one.
      ScrollableState? scrollable;
      if (targetContext != null) {
        final Element targetElement = targetContext as Element;
        if (targetElement.widget is Scrollable) {
          final State state = (targetElement as StatefulElement).state;
          if (state is ScrollableState && state.position.hasPixels) {
            scrollable = state;
          }
        }
        scrollable ??= Scrollable.maybeOf(targetContext);
        scrollable ??= _findScrollableDescendant(targetElement);
      } else {
        scrollable = _findRootScrollable();
      }

      if (scrollable == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          wrapErrorDetail(
            'No scrollable found in the widget tree.',
            DuskErrorEnvelope.notFound(
              ref: ref ?? 'scrollable',
              candidates: collectSnapshotCandidates(),
            ),
          ),
        );
      }

      final double target = scrollable.position.pixels + dy + dx;
      await aiTestScrollByDelta(scrollable, target);
      finalOffset = scrollable.position.pixels;
    }

    // 4. Wait for the UI to settle before returning.
    await WidgetsBinding.instance.endOfFrame;

    // 5. Embed post-action snapshot (opt-out via includeSnapshot:'false').
    final Map<String, dynamic> payload = <String, dynamic>{
      'scrolled': true,
      'finalOffset': finalOffset,
    };
    try {
      await _appendSnapshotIfRequested(payload, params);
    } catch (e) {
      developer.log(
        '[fluttersdk_dusk] ext.dusk.scroll: post-dispatch snapshot build '
        'swallowed: $e',
        name: 'fluttersdk_dusk',
      );
    }

    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.scroll error: $e\n$stackTrace',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Scrolls the [context]'s nearest ancestor [Scrollable] so that [context] is
/// visible, using [Scrollable.ensureVisible].
///
/// Extracted as a top-level function so widget tests can call it directly
/// without going through the VM Service extension channel.
///
/// Parameters:
/// - [alignment]: fractional position within the viewport (0 = leading edge,
///   0.5 = center, 1 = trailing edge). Defaults to `0.5`.
/// - [duration]: animation duration. Defaults to 300 ms.
Future<void> aiTestScrollEnsureVisible(
  BuildContext context, {
  double alignment = 0.5,
  Duration duration = const Duration(milliseconds: 300),
}) {
  return Scrollable.ensureVisible(
    context,
    alignment: alignment,
    duration: duration,
    curve: Curves.ease,
  );
}

/// Scrolls [scrollable] to [targetPixels] using [ScrollPosition.jumpTo].
///
/// Uses `jumpTo` (instant, no animation) rather than `animateTo` so that:
/// - Tests do not deadlock waiting for animation frames that only the test
///   framework can deliver.
/// - The MCP caller gets an immediate response without animation overhead.
///
/// Extracted as a top-level function so widget tests can call it directly
/// without going through the VM Service extension channel.
Future<void> aiTestScrollByDelta(
  ScrollableState scrollable,
  double targetPixels,
) async {
  scrollable.position.jumpTo(targetPixels);
}

/// Resolves a `ref` string to a [BuildContext] via [RefRegistry].
///
/// Handles both `e<N>` (snapshot-frame) and `q<N>` (re-resolvable query) refs.
/// For q-refs, re-executes the stored DuskQuery against the live tree.
/// Returns `null` when the ref is unknown / unmounted; callers fall back
/// to the root-scrollable walk in that case.
BuildContext? _resolveRefContext(String ref) {
  final RefEntry? entry =
      ref.startsWith('q') ? _resolveQueryToEntry(ref) : RefRegistry.lookup(ref);
  if (entry == null) return null;
  final Element element = entry.element;
  return element.mounted ? element : null;
}

/// Re-runs the stored predicates for a q-handle against the live tree and
/// returns the materialised RefEntry, or null when the predicates no
/// longer match.
RefEntry? _resolveQueryToEntry(String qRef) {
  final DuskQuery? query = RefRegistry.lookupQuery(qRef);
  if (query == null) return null;
  return resolveQuery(query);
}

/// Walks descendants of [element] depth-first and returns the first
/// [ScrollableState] whose position has attached pixels. Used as a fallback
/// when the caller passes a ref to a parent widget (e.g. a Scaffold or
/// Container wrapping a ListView) so the scroll resolves to the contained
/// Scrollable instead of erroring out.
ScrollableState? _findScrollableDescendant(Element element) {
  ScrollableState? found;
  void visitor(Element child) {
    if (found != null) return;
    if (child.widget is Scrollable) {
      final State state = (child as StatefulElement).state;
      if (state is ScrollableState && state.position.hasPixels) {
        found = state;
        return;
      }
    }
    child.visitChildElements(visitor);
  }

  element.visitChildElements(visitor);
  return found;
}

/// Finds the first [ScrollableState] reachable from the widget tree root.
///
/// Used when no `ref` parameter is supplied to `ext.dusk.scroll`. Walks the
/// element tree depth-first and returns the context of the first
/// [Scrollable]-typed widget whose [ScrollableState] has an attached position.
ScrollableState? _findRootScrollable() {
  ScrollableState? found;

  void visitor(Element element) {
    if (found != null) return;
    if (element.widget is Scrollable) {
      final state = (element as StatefulElement).state;
      if (state is ScrollableState && state.position.hasPixels) {
        found = state;
        return;
      }
    }
    element.visitChildElements(visitor);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visitor);
  return found;
}

// -----------------------------------------------------------------------------
// ext.dusk.select_option
// -----------------------------------------------------------------------------

/// Handler for the `ext.dusk.select_option` VM Service extension.
///
/// Resolves the element identified by [params] `ref`, walks its subtree to
/// locate a [DropdownButton] (or compatible select widget), and calls
/// `onChanged` with the supplied `value` — simulating a programmatic selection
/// without going through a hit-test or canvas coordinate.
///
/// Params:
/// - `ref`: RefRegistry key (`eN`) identifying the select element.
/// - `value`: the string value to select.
///
/// Returns `{ selected: true, value: '<value>' }` on success.
///
/// Must NOT use canvas hit-test coordinates to trigger the selection; the
/// widget's `onChanged` callback is the only safe hook.
Future<developer.ServiceExtensionResponse> aiTestSelectOptionHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Parse parameters.
    final String? ref = params['ref'];
    final String? value = params['value'];

    if (value == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'Missing required parameter: value.',
          DuskErrorEnvelope.missingParam('value'),
        ),
      );
    }

    // 2. Resolve target context — prefer ref lookup when RefRegistry lands;
    //    fall back to a tree search for any DropdownButton.
    BuildContext? targetContext = ref != null ? _resolveRefContext(ref) : null;

    // 3. Walk the element subtree to find and invoke the select widget.
    final bool invoked = targetContext != null
        ? aiTestSelectOptionInElement(targetContext, value: value)
        : _selectOptionInTree(value);

    if (!invoked) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'No selectable widget found for ref=$ref value=$value.',
          DuskErrorEnvelope.notFound(
            ref: ref ?? 'select',
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }

    // 4. Wait for the UI to settle.
    await WidgetsBinding.instance.endOfFrame;

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'selected': true,
        'value': value,
      }),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.select_option error: $e\n$stackTrace',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Invokes the `onChanged` callback of a [DropdownButton] found at or below
/// [context]'s element, passing [value] cast to the widget's type parameter.
///
/// Extracted as a top-level function so widget tests can call it directly
/// without the VM Service extension channel.
///
/// Returns `true` when a [DropdownButton] with a non-null `onChanged` was
/// found and invoked; `false` otherwise.
bool aiTestSelectOptionInElement(
  BuildContext context, {
  required String value,
}) {
  bool invoked = false;

  void visitor(Element element) {
    if (invoked) return;
    final Widget widget = element.widget;

    // DropdownButton<T> is the primary target. We cannot directly cast to
    // DropdownButton<dynamic> due to Dart's covariant generics, so we use
    // the runtime type name check followed by a dynamic dispatch.
    if (widget.runtimeType.toString().startsWith('DropdownButton')) {
      // Retrieve onChanged via dynamic — the generated getter is public.
      // ignore: avoid_dynamic_calls
      final dynamic onChanged = (widget as dynamic).onChanged;
      if (onChanged != null) {
        // ignore: avoid_dynamic_calls
        onChanged(value);
        invoked = true;
        return;
      }
    }

    element.visitChildElements(visitor);
  }

  final Element rootElement = context as Element;
  rootElement.visitChildElements(visitor);

  // Also check the element itself.
  if (!invoked) {
    visitor(rootElement);
  }

  return invoked;
}

/// Searches the entire widget tree for the first [DropdownButton] and invokes
/// its `onChanged` with [value].
///
/// Used when no `ref` is available. Returns `true` when a widget was found and
/// invoked.
bool _selectOptionInTree(String value) {
  bool invoked = false;

  void visitor(Element element) {
    if (invoked) return;
    final Widget widget = element.widget;

    if (widget.runtimeType.toString().startsWith('DropdownButton')) {
      // ignore: avoid_dynamic_calls
      final dynamic onChanged = (widget as dynamic).onChanged;
      if (onChanged != null) {
        // ignore: avoid_dynamic_calls
        onChanged(value);
        invoked = true;
        return;
      }
    }

    element.visitChildElements(visitor);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visitor);
  return invoked;
}
