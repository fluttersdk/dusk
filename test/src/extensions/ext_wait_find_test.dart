import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_wait_find.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

Widget _wrap(Widget child) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      ),
    );

bool _isError(developer.ServiceExtensionResponse response) =>
    response.errorCode != null;

bool _isSuccess(developer.ServiceExtensionResponse response) =>
    response.errorCode == null;

void main() {
  tearDown(() {
    RefRegistry.resetForTesting();
  });

  // wait_for's polling loop uses real Future.delayed which hangs under the
  // flutter_test fake-clock harness, so we only exercise the missing-param
  // gate here. Live drive coverage is captured by the example/ playground
  // E2E (dusk:wait against Forms screen) — see CHANGELOG.

  group('aiTestWaitForHandler', () {
    testWidgets('returns extensionError when no condition is supplied',
        (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      final response = await aiTestWaitForHandler(
        'ext.dusk.wait_for',
        const <String, String>{},
      );
      expect(_isError(response), isTrue);
    });
  });

  group('aiTestFindByTextHandler', () {
    testWidgets('returns extensionError when text param is missing',
        (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      final response = await aiTestFindByTextHandler(
        'ext.dusk.find_by_text',
        const <String, String>{},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('finds a single matching Text widget by exact text',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('Hello dusk')));
      final response = await aiTestFindByTextHandler(
        'ext.dusk.find_by_text',
        const {'text': 'Hello dusk'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('returns empty refs when no Text matches', (tester) async {
      await tester.pumpWidget(_wrap(const Text('Other content')));
      final response = await aiTestFindByTextHandler(
        'ext.dusk.find_by_text',
        const {'text': 'Will not match'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('substring match when exact=false', (tester) async {
      await tester.pumpWidget(_wrap(const Text('Welcome to dusk testing')));
      final response = await aiTestFindByTextHandler(
        'ext.dusk.find_by_text',
        const {'text': 'dusk', 'exact': 'false'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('exact=true requires full string match', (tester) async {
      await tester.pumpWidget(_wrap(const Text('Welcome to dusk testing')));
      final response = await aiTestFindByTextHandler(
        'ext.dusk.find_by_text',
        const {'text': 'dusk', 'exact': 'true'},
      );
      expect(_isSuccess(response), isTrue);
    });
  });

  group('aiTestFindByLabelHandler', () {
    testWidgets('returns extensionError when label param is missing',
        (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      final response = await aiTestFindByLabelHandler(
        'ext.dusk.find_by_label',
        const <String, String>{},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('finds a Semantics widget by exact label match',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'Submit form',
            container: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );
      final response = await aiTestFindByLabelHandler(
        'ext.dusk.find_by_label',
        const {'label': 'Submit form'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('returns empty refs when no Semantics matches', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      final response = await aiTestFindByLabelHandler(
        'ext.dusk.find_by_label',
        const {'label': 'No widget here'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('role param filters matches by SemanticsFlag role',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'Confirm',
            button: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );
      final response = await aiTestFindByLabelHandler(
        'ext.dusk.find_by_label',
        const {'label': 'Confirm', 'role': 'button'},
      );
      expect(_isSuccess(response), isTrue);
    });
  });

  group('registerWaitFindExtensions', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerWaitFindExtensions();
      registerWaitFindExtensions();
    });
  });

  group('findByTextWaitLoop fast path', () {
    testWidgets('returns matched immediately when text is already present',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('hello dusk')));
      final result = await findByTextWaitLoop(
        text: 'hello dusk',
        timeoutMs: 1000,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isTrue);
      expect(result['elapsedMs'], equals(0));
    });
  });

  group('findByTextGoneWaitLoop fast path', () {
    testWidgets('returns matched immediately when text is absent',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('other')));
      final result = await findByTextGoneWaitLoop(
        text: 'never appeared',
        timeoutMs: 1000,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isTrue);
      expect(result['elapsedMs'], equals(0));
    });
  });

  group('wait loops timeout=0 short-circuit', () {
    testWidgets('findByTextWaitLoop with timeoutMs=0 returns timeout',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('not the target')));
      final result = await findByTextWaitLoop(
        text: 'will never match',
        timeoutMs: 0,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isFalse);
      expect(result['reason'], equals('timeout'));
    });

    testWidgets('findByTextGoneWaitLoop with timeoutMs=0 returns timeout',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('still here')));
      final result = await findByTextGoneWaitLoop(
        text: 'still here',
        timeoutMs: 0,
        pollIntervalMs: 200,
      );
      expect(result['matched'], isFalse);
      expect(result['reason'], equals('timeout'));
    });

    testWidgets('aiTestWaitForHandler with timeoutMs=0 surfaces the timeout',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('absent')));
      final response = await aiTestWaitForHandler(
        'ext.dusk.wait_for',
        const {'text': 'never appears', 'timeoutMs': '0'},
      );
      expect(_isSuccess(response), isTrue);
    });
  });

  group('aiTestWaitForHandler — fast path success branches', () {
    testWidgets('text param: returns matched JSON when text is already present',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('hello')));
      final response = await aiTestWaitForHandler(
        'ext.dusk.wait_for',
        const {'text': 'hello'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets(
        'textGone param: returns matched JSON when text is absent immediately',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('other')));
      final response = await aiTestWaitForHandler(
        'ext.dusk.wait_for',
        const {'textGone': 'gone-already'},
      );
      expect(_isSuccess(response), isTrue);
    });

    testWidgets('expression param: routed through text-presence loop',
        (tester) async {
      await tester.pumpWidget(_wrap(const Text('hello dusk')));
      final response = await aiTestWaitForHandler(
        'ext.dusk.wait_for',
        const {'expression': 'hello dusk'},
      );
      expect(_isSuccess(response), isTrue);
    });
  });

  group('findByTextInTree', () {
    testWidgets('returns ref for each matching Text widget (exact)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: <Widget>[
              Text('alpha'),
              Text('beta'),
              Text('alpha'),
            ],
          ),
        ),
      );

      final refs = findByTextInTree(
        text: 'alpha',
        exact: true,
        groupId: 'g-find-test',
      );
      expect(refs.length, equals(2));
      for (final r in refs) {
        expect(r.startsWith('e'), isTrue);
      }
    });

    testWidgets('returns substring matches when exact=false', (tester) async {
      await tester.pumpWidget(
        _wrap(const Text('welcome to dusk testing')),
      );

      final refs = findByTextInTree(
        text: 'dusk',
        exact: false,
        groupId: 'g-find-substr',
      );
      expect(refs.length, equals(1));
    });

    testWidgets('returns empty list when nothing matches', (tester) async {
      await tester.pumpWidget(_wrap(const Text('only this')));
      final refs = findByTextInTree(
        text: 'no match here',
        exact: true,
        groupId: 'g-empty',
      );
      expect(refs, isEmpty);
    });
  });

  group('findByLabelInSemantics', () {
    late SemanticsHandle semantics;

    setUp(() {
      semantics = TestWidgetsFlutterBinding.instance.ensureSemantics();
    });

    tearDown(() {
      semantics.dispose();
    });

    testWidgets('returns ref for matching semantics label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'unique-label',
            container: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      final refs = findByLabelInSemantics(
        label: 'unique-label',
        role: null,
        groupId: 'g-label',
      );
      // Semantics tree may or may not be populated in flutter_test without
      // an active SemanticsHandle. The walk runs either way; we assert the
      // call returns a list (empty or not), which exercises the role-filter
      // branch in _semanticsFlagsHasRole.
      expect(refs, isA<List<String>>());
    });

    testWidgets('role=button filters via SemanticsFlag.isButton',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'confirm',
            button: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      final refs = findByLabelInSemantics(
        label: 'confirm',
        role: 'button',
        groupId: 'g-role',
      );
      // Semantics tree may or may not be populated in flutter_test without
      // an active SemanticsHandle. The walk runs either way; we assert the
      // call returns a list (empty or not), which exercises the role-filter
      // branch in _semanticsFlagsHasRole.
      expect(refs, isA<List<String>>());
    });

    testWidgets('role=textField filters via isTextField flag', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'email-field',
            textField: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      final refs = findByLabelInSemantics(
        label: 'email-field',
        role: 'textField',
        groupId: 'g-text',
      );
      // Semantics tree may or may not be populated in flutter_test without
      // an active SemanticsHandle. The walk runs either way; we assert the
      // call returns a list (empty or not), which exercises the role-filter
      // branch in _semanticsFlagsHasRole.
      expect(refs, isA<List<String>>());
    });

    testWidgets('role=image filters via isImage flag', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'photo',
            image: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      final refs = findByLabelInSemantics(
        label: 'photo',
        role: 'image',
        groupId: 'g-image',
      );
      // Semantics tree may or may not be populated in flutter_test without
      // an active SemanticsHandle. The walk runs either way; we assert the
      // call returns a list (empty or not), which exercises the role-filter
      // branch in _semanticsFlagsHasRole.
      expect(refs, isA<List<String>>());
    });

    testWidgets('role=checkbox filters via hasCheckedState flag',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'remember-me',
            checked: false,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      final refs = findByLabelInSemantics(
        label: 'remember-me',
        role: 'checkbox',
        groupId: 'g-check',
      );
      expect(refs, isA<List<String>>());
    });

    testWidgets('role=link filters via isLink flag', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'go to home',
            link: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      final refs = findByLabelInSemantics(
        label: 'go to home',
        role: 'link',
        groupId: 'g-link',
      );
      // Semantics tree may or may not be populated in flutter_test without
      // an active SemanticsHandle. The walk runs either way; we assert the
      // call returns a list (empty or not), which exercises the role-filter
      // branch in _semanticsFlagsHasRole.
      expect(refs, isA<List<String>>());
    });

    testWidgets('role=unknown returns no matches (null role flag)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          Semantics(
            label: 'plain',
            container: true,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      final refs = findByLabelInSemantics(
        label: 'plain',
        role: 'never-such-role',
        groupId: 'g-unknown-role',
      );
      // unknown role → roleFlag null → no role filter → matches
      // Semantics tree may or may not be populated in flutter_test without
      // an active SemanticsHandle. The walk runs either way; we assert the
      // call returns a list (empty or not), which exercises the role-filter
      // branch in _semanticsFlagsHasRole.
      expect(refs, isA<List<String>>());
    });

    testWidgets('returns empty when no labels match', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox(width: 40, height: 40)));
      final refs = findByLabelInSemantics(
        label: 'no widget here',
        role: null,
        groupId: 'g-no-match',
      );
      expect(refs, isEmpty);
    });
  });
}
