import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_fill.dart';
import 'package:tapir/src/extensions/ext_snapshot.dart';
import 'package:tapir/src/ref_registry.dart';
import 'package:tapir/src/utils/error_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tapirFillHandler', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'focus + clear + type into a TextField in one call returns the typed text',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController(
          text: 'old value',
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );

        final Element element = tester.element(find.byType(TextField));
        final String ref = registerRefForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: element,
          groupId: 'g',
          isTextField: true,
        );

        // The handler chains focus + clear + type, each awaiting one or two
        // endOfFrame ticks; pump alongside so frames advance under fake-async.
        // checkStable / checkReceivesEvents opt-out: the synthetic rect does
        // not align with the live TextField geometry.
        final future = tapirFillHandler('ext.tapir.fill', <String, String>{
          'ref': ref,
          'text': 'fresh text',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'includeSnapshot': 'false',
        });
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> json =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(json['ref'], equals(ref));
        expect(json['text'], equals('fresh text'));
        expect(json['filled'], isTrue);
        expect(controller.text, equals('fresh text'));
      },
    );

    testWidgets(
      'carries the type step\'s gate checks, so a skipped or indeterminate '
      'receives-events check is not read as a clean pass',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );

        final String ref = registerRefForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: tester.element(find.byType(TextField)),
          groupId: 'g',
          isTextField: true,
        );

        final future = tapirFillHandler('ext.tapir.fill', <String, String>{
          'ref': ref,
          'text': 'checked',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'includeSnapshot': 'false',
        });
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final Map<String, dynamic> json =
            jsonDecode((await future).result!) as Map<String, dynamic>;

        expect(
          json['checks'],
          equals(<String, dynamic>{'receivesEvents': 'skipped'}),
        );
      },
    );

    testWidgets('missing ref returns a missing-param error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final response = await tapirFillHandler(
        'ext.tapir.fill',
        const <String, String>{'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
    });

    testWidgets('unknown ref returns a not-found error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final response = await tapirFillHandler(
        'ext.tapir.fill',
        const <String, String>{'ref': 'e999', 'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('not found in registry'));
    });

    testWidgets('resolves a q-handle against the live tree and fills it', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TextField(
                key: const ValueKey<String>('fill-field'),
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final String ref = RefRegistry.registerQuery(
        const TapirQuery(keyValue: 'fill-field'),
      );

      final future = tapirFillHandler('ext.tapir.fill', <String, String>{
        'ref': ref,
        'text': 'retry value',
        'checkStable': 'false',
        'checkReceivesEvents': 'false',
        'includeSnapshot': 'false',
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      final response = await future;

      expect(response.result, isNotNull);
      final Map<String, dynamic> json =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json['text'], equals('retry value'));
      expect(controller.text, equals('retry value'));

      // The type step read the controller back; fill carries that verdict
      // up rather than restating `filled: true`, which only says the
      // focus + clear + type sequence ran.
      final Map<String, dynamic> effect =
          json['effect'] as Map<String, dynamic>;
      expect(effect['kind'], equals('text'));
      expect(effect['verified'], isTrue);
      expect(effect['value'], equals('retry value'));
    });

    testWidgets(
      'a permanently stale q-handle surfaces a stale error after the retry',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));

        // No matching widget exists, so both the first attempt and the retry
        // fail to resolve the handle.
        final String ref = RefRegistry.registerQuery(
          const TapirQuery(keyValue: 'never-matches'),
        );

        final response = await tapirFillHandler(
          'ext.tapir.fill',
          <String, String>{
            'ref': ref,
            'text': 'whatever',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('"type":"stale"'));
      },
    );

    testWidgets(
      'snapshot=diff answers the field against the snapshot before the fill',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        resetSnapshotBaselineForTesting();
        addTearDown(resetSnapshotBaselineForTesting);

        final TextEditingController controller = TextEditingController(
          text: 'before',
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );
        await tapirSnapBuild();

        final Element element = tester.element(find.byType(TextField));
        final String ref = registerRefForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: element,
          groupId: 'g',
          isTextField: true,
        );

        final future = tapirFillHandler('ext.tapir.fill', <String, String>{
          'ref': ref,
          'text': 'after',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'snapshot': 'diff',
        });
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final response = await future;

        final Map<String, dynamic> json =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(json['snapshotMode'], 'diff');
        // The clear and type steps build no snapshot of their own, so the
        // baseline is still the pre-fill one and the old value shows.
        final String diff = json['snapshot'] as String;
        expect(diff, contains('"before"'));
        expect(diff, contains('"after"'));
        expect(diff, endsWith('lines changed)'));
      },
    );

    testWidgets('snapshot=none overrides includeSnapshot true', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: TextField(controller: controller)),
          ),
        ),
      );

      final Element element = tester.element(find.byType(TextField));
      final String ref = registerRefForTesting(
        rect: const Rect.fromLTWH(100, 100, 200, 40),
        element: element,
        groupId: 'g',
        isTextField: true,
      );

      final future = tapirFillHandler('ext.tapir.fill', <String, String>{
        'ref': ref,
        'text': 'x',
        'checkStable': 'false',
        'checkReceivesEvents': 'false',
        'includeSnapshot': 'true',
        'snapshot': 'none',
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      final response = await future;

      final Map<String, dynamic> json =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json.containsKey('snapshot'), isFalse);
    });
  });

  group('tapirFillHandler on a ref that is not a text field', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('a dropdown ref is refused and the Name field keeps its text', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TextEditingController name = TextEditingController(text: 'Ada');
      addTearDown(name.dispose);
      await tester.pumpWidget(_DropdownForm(name: name));

      final String ref = _registerNodeRef(
        tester,
        find.byType(DropdownButton<String>),
      );
      final response = await _drive(
        tester,
        tapirFillHandler('ext.tapir.fill', _quietParams(ref, 'Bob')),
      );

      expect(response.result, isNull);
      expect(
        parseMessageFromErrorDetail(response.errorDetail ?? ''),
        contains('ref $ref is a button, not a text field'),
      );
      expect(name.text, equals('Ada'));
      semantics.dispose();
    });

    testWidgets(
      'a label ref fills the adjacent field and reports it as nearest',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TextEditingController name = TextEditingController(text: 'old');
        addTearDown(name.dispose);
        await tester.pumpWidget(_LabelledForm(name: name));

        final String ref = _registerNodeRef(tester, find.text('Full name'));
        final response = await _drive(
          tester,
          tapirFillHandler('ext.tapir.fill', _quietParams(ref, 'Ada')),
        );

        expect(response.result, isNotNull, reason: response.errorDetail);
        expect(name.text, equals('Ada'));
        final Map<String, dynamic> effect =
            (jsonDecode(response.result!) as Map<String, dynamic>)['effect']
                as Map<String, dynamic>;
        expect(effect['verified'], isTrue);
        expect(
          (effect['target'] as Map<String, dynamic>)['matchKind'],
          equals('nearest'),
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'a field ref clears and types the same field, not the first one',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TextEditingController first = TextEditingController(text: 'one');
        final TextEditingController second = TextEditingController(text: 'two');
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  TextField(controller: first),
                  TextField(controller: second),
                ],
              ),
            ),
          ),
        );

        // The textbox node sits on the EditableText; the snapshot mints the
        // field's ref from it.
        final String ref = _registerNodeRef(
          tester,
          find.byType(EditableText).at(1),
        );
        final response = await _drive(
          tester,
          tapirFillHandler('ext.tapir.fill', _quietParams(ref, 'fresh')),
        );

        expect(response.result, isNotNull, reason: response.errorDetail);
        expect(second.text, equals('fresh'));
        expect(first.text, equals('one'));
        semantics.dispose();
      },
    );
  });

  group('registerFillExtension', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerFillExtension();
      registerFillExtension();
    });
  });
}

/// Gate opt-outs for a test-minted ref, whose rect is not re-validated.
Map<String, String> _quietParams(String ref, String text) => <String, String>{
  'ref': ref,
  'text': text,
  'checkStable': 'false',
  'checkReceivesEvents': 'false',
  'includeSnapshot': 'false',
};

/// Registers an `e<N>` ref the way a snapshot mints one from a semantics
/// node: the node and its rect, carried by the app-root element.
String _registerNodeRef(WidgetTester tester, Finder finder) =>
    RefRegistry.register(
      rect: tester.getRect(finder),
      element: WidgetsBinding.instance.rootElement!,
      groupId: 'g',
      isTextField: false,
      node: tester.getSemantics(finder),
    );

/// Pumps frames until [pending] completes, so a handler's frame waits land.
Future<developer.ServiceExtensionResponse> _drive(
  WidgetTester tester,
  Future<developer.ServiceExtensionResponse> pending,
) async {
  bool done = false;
  unawaited(pending.whenComplete(() => done = true));
  for (int i = 0; i < 30 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  return pending;
}

/// A Name field above a dropdown, the F-23 shape: the dropdown's rect overlaps
/// no editable, so fill used to clear and write the Name field instead.
class _DropdownForm extends StatelessWidget {
  const _DropdownForm({required this.name});

  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 40),
            DropdownButton<String>(
              value: 'apple',
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'apple', child: Text('Apple')),
                DropdownMenuItem<String>(value: 'pear', child: Text('Pear')),
              ],
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

/// A static label above a field it does not overlap, the handle shape a find
/// by label text returns.
class _LabelledForm extends StatelessWidget {
  const _LabelledForm({required this.name});

  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            Semantics(container: true, child: const Text('Full name')),
            const SizedBox(height: 24),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ),
      ),
    );
  }
}
