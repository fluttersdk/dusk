import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_pointer.dart';
import 'package:tapir/src/ref_registry.dart';

const Key _triggerKey = Key('trigger');
const Key _panelKey = Key('panel');
const Key _outsideKey = Key('outside');

/// A popover that copies the dismiss guard of `WPopover` without importing it.
///
/// What is mimicked (wind `w_popover.dart` `open`, `_handleTapOutside`,
/// `_buildTrigger`):
/// - the trigger toggles from a [Listener] on pointer-down, filtered to
///   `kPrimaryButton`;
/// - `open` arms `_suppressNextTapOutside` and disarms it in ONE post-frame
///   callback;
/// - the overlay panel sits in a [TapRegion] that shares a `groupId` with the
///   trigger and whose `onTapOutside` swallows one event while armed, else
///   closes.
///
/// Every step is appended to [events] so a test can assert on ordering, not
/// only on the end state.
class _GuardedPopover extends StatefulWidget {
  const _GuardedPopover({required this.events});

  final List<String> events;

  @override
  State<_GuardedPopover> createState() => _GuardedPopoverState();
}

class _GuardedPopoverState extends State<_GuardedPopover> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final Object _groupId = Object();
  bool _isOpen = false;
  bool _suppressNextTapOutside = false;

  void _toggle() => _isOpen ? _close() : _open();

  void _open() {
    widget.events.add('open');
    _suppressNextTapOutside = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.events.add('disarm');
      _suppressNextTapOutside = false;
    });

    setState(() {
      _isOpen = true;
      _overlay.show();
    });
  }

  void _close() {
    widget.events.add('close');
    _suppressNextTapOutside = false;
    setState(() {
      _isOpen = false;
      _overlay.hide();
    });
  }

  void _handleTapOutside() {
    widget.events.add('tapOutside(armed=$_suppressNextTapOutside)');
    if (_suppressNextTapOutside) {
      _suppressNextTapOutside = false;
      return;
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (BuildContext context) {
        return Positioned(
          left: 0,
          top: 60,
          child: TapRegion(
            groupId: _groupId,
            onTapOutside: (_) => _handleTapOutside(),
            // Recorded only: WPopover wires no onTapUpOutside, this shows
            // what the up half of the hold would have done if it had.
            onTapUpOutside: (_) => widget.events.add(
              'tapUpOutside(armed=$_suppressNextTapOutside)',
            ),
            child: const SizedBox(key: _panelKey, width: 200, height: 100),
          ),
        );
      },
      child: TapRegion(
        groupId: _groupId,
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            widget.events.add('down(buttons=${event.buttons})');
            if (event.buttons == kPrimaryButton) _toggle();
          },
          // A bare SizedBox is not hit-testable; a real trigger paints content.
          child: const SizedBox(
            key: _triggerKey,
            width: 120,
            height: 40,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
  }
}

Widget _screen(List<String> events) {
  return MaterialApp(
    home: Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => events.add('up'),
        child: Stack(
          children: <Widget>[
            Positioned(left: 0, top: 0, child: _GuardedPopover(events: events)),
            const Positioned(
              right: 0,
              bottom: 0,
              child: SizedBox(key: _outsideKey, width: 100, height: 100),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Taps [key] with `ext.tapir.tap`, pumping frames across the 50 ms hold.
///
/// Gates are opted out because the ref is minted by `registerForTesting`,
/// whose rect is the widget's own but whose semantics node is synthetic.
Future<void> _tapirTap(WidgetTester tester, Key key) async {
  final String ref = RefRegistry.registerForTesting(
    rect: tester.getRect(find.byKey(key)),
    element: tester.element(find.byKey(key)),
    groupId: 'g',
    isTextField: false,
  );

  final Future<void> done = aiTestTapHandler('ext.tapir.tap', <String, String>{
    'ref': ref,
    'checkStable': 'false',
    'checkReceivesEvents': 'false',
    'includeSnapshot': 'false',
  });
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await done;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aiTestTapHandler against a WPopover-style dismiss guard', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'the 50 ms hold outlives the guard yet the popover stays open',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<String> events = <String>[];
        await tester.pumpWidget(_screen(events));

        await _tapirTap(tester, _triggerKey);

        // The guard is disarmed by a frame that ran inside the hold, i.e.
        // BEFORE the pointer-up: the hypothesis premise holds.
        expect(events, <String>['down(buttons=1)', 'open', 'disarm', 'up']);
        // The overlay TapRegion never saw the opening down (it did not exist
        // when that down was hit-tested), and WPopover reads only the down
        // half, so nothing closed the popover.
        expect(events.where((String e) => e.startsWith('tapOutside')), isEmpty);
        expect(events, isNot(contains('close')));
        expect(find.byKey(_panelKey), findsOneWidget);
      },
    );

    testWidgets(
      'the opening up is inside the trigger group, so no outside-up fires',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<String> events = <String>[];
        await tester.pumpWidget(_screen(events));

        await _tapirTap(tester, _triggerKey);

        // The trigger shares the overlay's groupId, so its own up is inside
        // the group: not even onTapUpOutside fires for the opening gesture.
        expect(
          events.where((String e) => e.startsWith('tapUpOutside')),
          isEmpty,
        );
      },
    );

    testWidgets(
      'a later outside tap closes the popover, so the guard did not stick',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<String> events = <String>[];
        await tester.pumpWidget(_screen(events));
        await _tapirTap(tester, _triggerKey);
        events.clear();

        await _tapirTap(tester, _outsideKey);
        await tester.pump();

        expect(events, <String>['tapOutside(armed=false)', 'close', 'up']);
        expect(find.byKey(_panelKey), findsNothing);
      },
    );
  });
}
