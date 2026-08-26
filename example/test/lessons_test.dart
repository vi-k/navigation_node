import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_node/navigation_node.dart';
import 'package:navigation_node_example/journal.dart';
import 'package:navigation_node_example/main.dart';
import 'package:navigation_node_example/system_back.dart';

/// Presses the panel's own System back, not the ones inside pages.
Future<void> pressSystemBackButton(WidgetTester tester) async {
  await tester.tap(find.byType(SystemBackButton).first);
  await tester.pumpAndSettle();
}

Future<void> openLesson(WidgetTester tester, String title) async {
  await tester.pumpWidget(const NavigationNodeApp());
  await tester.pumpAndSettle();
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}

void main() {
  group('on a small window', () {
    setUp(() {
      // A node's dialog is drawn inside the node's own box, which is a slice of
      // an already small window. Anything that does not fit throws here.
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        ..physicalSize = const Size(800, 600)
        ..devicePixelRatio = 1.0;
    });

    testWidgets('lesson 2: both dialogs fit inside the node', (tester) async {
      await openLesson(tester, lessons[1].title);

      await tester.tap(find.text('Dialog in the node'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await pressSystemBackButton(tester);
      await tester.tap(find.text('Dialog on the application'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('lesson 4: the onPop dialog belongs to the node and fits in it',
        (tester) async {
      await openLesson(tester, lessons[3].title);

      await pressSystemBackButton(tester);

      final dialog = find.ancestor(
        of: find.text('Leave this lesson?'),
        matching: find.byType(AlertDialog),
      );
      expect(dialog, findsOneWidget);

      // `useRootNavigator: false` means the node's navigator, and that is the
      // whole reason to ask here rather than anywhere else: everything the
      // node stands under is above the dialog too. Asked from a context
      // outside the node the same call lands on the application's navigator,
      // and this is what tells the two apart.
      expect(
        find.descendant(of: find.byType(NavigationNode), matching: dialog),
        findsOneWidget,
      );

      final nodeBox = tester.getRect(find.byType(NavigationNode));
      expect(
        nodeBox.expandToInclude(tester.getRect(dialog)),
        nodeBox,
        reason: "and being the node's means being drawn in the node's box, "
            'which is a slice of an already small window',
      );

      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
    });
  });

  setUp(() {
    // Two lessons put two stages side by side; the default 800x600 is not
    // enough for their buttons to be hit-testable.
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(1400, 1600)
      ..devicePixelRatio = 1.0;
  });

  for (final lesson in lessons) {
    testWidgets('${lesson.title} opens and takes a system back',
        (tester) async {
      await openLesson(tester, lesson.title);
      expect(find.byType(SystemBackButton), findsWidgets);

      await pressSystemBackButton(tester);

      // Whether the lesson kept the back or let it out, something is on
      // screen. An emptied navigator draws nothing at all.
      expect(find.byType(Scaffold), findsWidgets);
    });
  }

  testWidgets('lesson 1: the back closes the page inside the node only',
      (tester) async {
    await openLesson(tester, lessons[0].title);

    await tester.tap(find.text('Push a page').last);
    await tester.pumpAndSettle();
    expect(find.text('Pushed inside the node'), findsOneWidget);

    await pressSystemBackButton(tester);

    expect(find.text('Pushed inside the node'), findsNothing);
    expect(
      find.text(lessons[0].title),
      findsWidgets,
      reason: 'the lesson itself must still be on screen',
    );
  });

  testWidgets('lesson 1: only the page inside the node reaches the scope',
      (tester) async {
    await openLesson(tester, lessons[0].title);

    await tester.tap(find.text('Push a page').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('out of reach'),
      findsOneWidget,
      reason: 'pushed above the screen, so the screen scope is not an ancestor',
    );

    await pressSystemBackButton(tester);
    await tester.tap(find.text('Push a page').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('ticket A-42'),
      findsWidgets,
      reason: 'pushed inside the node, so the screen scope is still above it',
    );
  });

  testWidgets('lesson 5: a root node has no back arrow, an ordinary one does',
      (tester) async {
    await openLesson(tester, lessons[4].title);

    Finder arrowIn(String barTitle) => find.descendant(
          of: find.ancestor(
            of: find.text(barTitle),
            matching: find.byType(AppBar),
          ),
          matching: find.byType(BackButton),
        );

    expect(
      arrowIn('ordinary node — arrow'),
      findsOneWidget,
      reason: 'a forwarding node marks its first page as having a way out, '
          'and that is what the arrow reads',
    );
    expect(
      arrowIn('root node — no arrow'),
      findsNothing,
      reason: 'a root node has nowhere to forward to',
    );
  });

  testWidgets('lesson 2: the back closes a dialog opened in the node',
      (tester) async {
    await openLesson(tester, lessons[1].title);

    await tester.tap(find.text('Dialog in the node'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog in the node').hitTestable(), findsWidgets);

    await pressSystemBackButton(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(lessons[1].title), findsWidgets);
  });

  testWidgets('lesson 3: a page that refuses keeps the back', (tester) async {
    await openLesson(tester, lessons[2].title);

    await tester.tap(find.text('Push the guarded page'));
    await tester.pumpAndSettle();
    expect(find.text('Guarded: back does nothing'), findsOneWidget);

    await pressSystemBackButton(tester);

    expect(
      find.text('Guarded: back does nothing'),
      findsOneWidget,
      reason: 'the node asked the page, and the page said no',
    );
  });

  testWidgets('lesson 4: onPop is asked exactly once', (tester) async {
    await openLesson(tester, lessons[3].title);
    expect(find.text('onPop asked 0 times'), findsOneWidget);

    await pressSystemBackButton(tester);

    expect(find.text('Leave this lesson?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    expect(find.text('onPop asked 1 time'), findsOneWidget);
    expect(
      find.text(lessons[3].title),
      findsWidgets,
      reason: 'onPop answered "stay", so the lesson stays',
    );
  });

  testWidgets('lesson 4: onPop is not asked while the node has a page',
      (tester) async {
    await openLesson(tester, lessons[3].title);

    await tester.tap(find.text('Push a page inside first'));
    await tester.pumpAndSettle();

    await pressSystemBackButton(tester);

    expect(find.text('Leave this lesson?'), findsNothing);
    expect(find.text('onPop asked 0 times'), findsOneWidget);
  });

  testWidgets(
      'lesson 5: a root node keeps the pop, an ordinary one forwards it',
      (tester) async {
    await openLesson(tester, lessons[4].title);

    // The right-hand stage is the root node: its box must keep its content.
    await tester.tap(find.text('pop() the first page').last);
    await tester.pumpAndSettle();

    expect(
      find.text('keeps the pop'),
      findsOneWidget,
      reason: 'a root node must not empty its own box',
    );
    expect(find.text(lessons[4].title), findsWidgets);

    // The left-hand one forwards, which here closes the lesson.
    await tester.tap(find.text('pop() the first page').first);
    await tester.pumpAndSettle();

    expect(
      find.text('keeps the pop'),
      findsNothing,
      reason: 'the forwarded pop closed the lesson around the node',
    );
  });

  testWidgets('lesson 6: the back reaches the innermost node', (tester) async {
    await openLesson(tester, lessons[5].title);

    await tester.tap(find.text('Push in the INNER node'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push in the OUTER node'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed in the outer node'), findsOneWidget);

    // Top first: the outer page covers the inner node.
    await pressSystemBackButton(tester);
    expect(find.text('Pushed in the outer node'), findsNothing);
    expect(find.text('Pushed in the inner node'), findsOneWidget);

    await pressSystemBackButton(tester);
    expect(find.text('Pushed in the inner node'), findsNothing);
    expect(
      find.text(lessons[5].title),
      findsWidgets,
      reason: 'neither back left the lesson',
    );
  });
  testWidgets('lesson 7: only the visible tab answers the back',
      (tester) async {
    await openLesson(tester, lessons[6].title);

    await tester.tap(find.text('Push a page in tab A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tab B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push a page in tab B'));
    await tester.pumpAndSettle();

    await pressSystemBackButton(tester);
    expect(find.text('Pushed in tab B'), findsNothing);

    await tester.tap(find.text('Tab A'));
    await tester.pumpAndSettle();

    expect(
      find.text('Pushed in tab A'),
      findsOneWidget,
      reason: 'the hidden tab is disabled, so it took no part in the press',
    );
  });

  testWidgets('lesson 7: without enabled every tab answers it', (tester) async {
    await openLesson(tester, lessons[6].title);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push a page in tab A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tab B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push a page in tab B'));
    await tester.pumpAndSettle();

    await pressSystemBackButton(tester);

    await tester.tap(find.text('Tab A'));
    await tester.pumpAndSettle();

    expect(
      find.text('Pushed in tab A'),
      findsNothing,
      reason: 'every node on the route was asked and called back, so the tab '
          'nobody was looking at lost a page too',
    );
  });

  testWidgets('lesson 8: the same name lands under the screen only inside',
      (tester) async {
    await openLesson(tester, lessons[7].title);

    await tester.tap(find.text('pushNamed inside the node'));
    await tester.pumpAndSettle();
    expect(find.text('Built from the route table'), findsOneWidget);
    expect(
      find.textContaining('ticket N-7'),
      findsWidgets,
      reason: 'the node borrowed the table and built the name below itself',
    );

    await pressSystemBackButton(tester);
    await tester.tap(find.text('pushNamed on the application'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('out of reach'),
      findsOneWidget,
      reason: 'the same name on the navigator above lands above the screen',
    );
  });

  testWidgets('lesson 9: the application hears the node until told not to',
      (tester) async {
    await openLesson(tester, lessons[8].title);

    final journal = JournalScope.of(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );

    await tester.tap(find.text('Push a page inside the node'));
    await tester.pumpAndSettle();

    expect(
      journal.entries.map((entry) => entry.message),
      containsAll([
        'the observer of the application heard: pushed "observed page"',
        'the observer given to the node heard: pushed "observed page"',
      ]),
    );

    await pressSystemBackButton(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    journal.clear();
    await tester.pump();

    await tester.tap(find.text('Push a page inside the node'));
    await tester.pumpAndSettle();

    final heard = journal.entries.map((entry) => entry.message).toList();
    expect(
      heard,
      contains('the observer given to the node heard: pushed "observed page"'),
      reason: 'what the node was given hears it whatever the switch says',
    );
    expect(
      heard,
      isNot(
        contains(
          'the observer of the application heard: pushed "observed page"',
        ),
      ),
      reason: 'and observedFromAbove: false is what stops the rest',
    );
  });
  testWidgets('lesson 10: only the restorable push comes back', (tester) async {
    await openLesson(tester, lessons[9].title);

    await tester.tap(find.text('Push restorably'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed restorably'), findsOneWidget);

    await tester.tap(find.text('Kill and bring it back'));
    await tester.pumpAndSettle();

    expect(
      find.text('Pushed restorably'),
      findsOneWidget,
      reason: 'the page was written down and built again from what was kept',
    );
  });

  testWidgets('lesson 10: an ordinary push is not written down anywhere',
      (tester) async {
    await openLesson(tester, lessons[9].title);

    await tester.tap(find.text('Push the ordinary way'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed the ordinary way'), findsOneWidget);

    await tester.tap(find.text('Kill and bring it back'));
    await tester.pumpAndSettle();

    expect(
      find.text('Pushed the ordinary way'),
      findsNothing,
      reason: 'a closure cannot be written down, so there was nothing to '
          'build again — the framework says so, not the node',
    );
    expect(
      find.text('first page of the node'),
      findsOneWidget,
      reason: 'and the node is where a fresh start would leave it',
    );
  });
}
