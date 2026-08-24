import 'dart:async';

// `ValueListenable` is not exported from `material.dart`; the guard below
// implements it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_node/navigation_node.dart';

void main() {
  group('NavigationNode', () {
    testWidgets('a screen pushed inside the node still sees the scope above it',
        (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.text('pushed: secret'),
        findsOneWidget,
        reason: 'the nested navigator lives below the scope, so the route it '
            'pushes does too',
      );
    });

    testWidgets(
      'control: the same screen pushed on the root navigator does not',
      (tester) async {
        await tester.pumpWidget(const _Host(useNode: false));

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          find.text('pushed: none'),
          findsOneWidget,
          reason: 'the root navigator sits above the scope, and this is the '
              'whole reason NavigationNode exists',
        );
      },
    );

    testWidgets('popping inside the node returns to the node content', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsNothing);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(find.text('pushed: secret'), findsNothing);
    });

    testWidgets('system back pops a pushed route inside the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed: secret'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('pushed: secret'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('system back closes a dialog inside the node', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('dialog'), findsNothing);
      expect(find.text('open dialog'), findsOneWidget);
    });

    // A drawer is not a route: it puts a local history entry on the route it
    // is on, and nothing tells any navigator its stack has changed. Without a
    // node around it the back gesture closes it, and the node must not be what
    // takes that away.
    testWidgets('system back closes a drawer inside the node', (tester) async {
      await tester.pumpWidget(const _DrawerHost(useNode: true));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('drawer'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('drawer'),
        findsNothing,
        reason: 'the press belongs to the drawer, which is what the route the '
            'node sits on would close on its own',
      );
      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'and the route around the node has to stay: the node must not '
            'take away what works without it',
      );
    });

    // Several nodes on one route, of which one is on screen: a node per tab of
    // an `IndexedStack`, which keeps the branches it does not show mounted. A
    // route asks every `PopEntry` it has and calls every one of them back, so
    // one press unwound the stack of every node on the route at once.
    //
    // Which one is on screen is not something a node can find out --
    // `TickerMode` and `ModalRoute` read the same in a hidden branch as in a
    // shown one -- so the application says it, and `enabled` is where.
    testWidgets('a back press reaches only the node that is enabled',
        (tester) async {
      await tester.pumpWidget(const _TabbedNodesHost(useEnabled: true));

      await tester.tap(find.text('push tab0'));
      await tester.pumpAndSettle();
      expect(find.text('tab0 inner'), findsOneWidget);

      await tester.tap(find.text('switch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('push tab1'));
      await tester.pumpAndSettle();
      expect(find.text('tab1 inner'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('tab1 inner'),
        findsNothing,
        reason: 'the node on screen took the press',
      );
      expect(
        find.text('tab0 inner', skipOffstage: false),
        findsOneWidget,
        reason: 'and the hidden one kept its stack, though it is still '
            'mounted and still holds a navigator of its own',
      );
    });

    // The control, and the reason `enabled` exists: with both nodes taking
    // part, the same press unwinds both stacks. This is Flutter's own
    // behaviour for two `PopScope`s on one route, and it is what an
    // application asks for by leaving `enabled` alone.
    testWidgets('control: without it the press reaches both nodes',
        (tester) async {
      await tester.pumpWidget(const _TabbedNodesHost(useEnabled: false));

      await tester.tap(find.text('push tab0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('switch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('push tab1'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('tab1 inner'), findsNothing);
      expect(
        find.text('tab0 inner', skipOffstage: false),
        findsNothing,
        reason: 'the hidden node was asked about the same press and acted on '
            'it, which is the whole of the finding',
      );
    });

    // The same press, one layer up: the drawer belongs to the route the node
    // stands on rather than to a route inside it. A node with `onPop` said
    // `doNotPop` unconditionally, so the route never got as far as the local
    // history the drawer had put on it -- and the node was asked "leave this
    // screen?" about a press whose whole job was to close a drawer. Refuse,
    // and the drawer could not be closed with back at all.
    testWidgets(
      'system back closes a drawer above a node with onPop',
      (tester) async {
        final log = <String>[];

        await tester.pumpWidget(_DrawerAboveNodeHost(log: log));

        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(find.text('drawer'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          find.text('drawer'),
          findsNothing,
          reason: 'the route would have closed the drawer on its own, and a '
              'node standing on it must not take that away',
        );
        expect(
          log,
          isEmpty,
          reason: 'and the node is not asked about a press that never left '
              'the route it stands on',
        );
        expect(find.text('node content'), findsOneWidget);
      },
    );

    testWidgets(
      'control: the same drawer without a node closes on system back',
      (tester) async {
        await tester.pumpWidget(const _DrawerHost(useNode: false));

        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(find.text('drawer'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.text('drawer'), findsNothing);
        expect(find.text('node content'), findsOneWidget);
      },
    );

    // The node's first page is the first route of its own navigator, so
    // nothing about that navigator implies a way back. The node says there is
    // one for the page itself, because pressing it leaves the node.
    testWidgets('an AppBar on the first page of a node draws a back arrow',
        (tester) async {
      await tester.pumpWidget(const _AppBarHost());

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the arrow leaves the node, which is the only thing it could '
            'mean on a page that is the first of its navigator',
      );
    });

    testWidgets('a root node draws no back arrow on its first page', (
      tester,
    ) async {
      await tester.pumpWidget(const _AppBarHost(isRoot: true));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        find.byType(BackButton),
        findsNothing,
        reason: 'a root node keeps a pop to itself, so there is nowhere for '
            'an arrow on its first page to go',
      );
    });

    // The promise "a root node keeps a pop to itself" lives in two places, and
    // only one of them was held down: `pop` was, `maybePop` was not, and
    // removing the guard from it left the whole suite green. `maybePop` is the
    // path the back arrow of an `AppBar` takes and the one a caller holding
    // the `navigatorKey` takes, and on a root node it would push the pop out
    // of the node and take the route the node stands on with it.
    testWidgets('a root node keeps a maybePop to itself, not only a pop',
        (tester) async {
      final key = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(_RootNodeKeyHost(navigatorKey: key));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      final answered = await key.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(
        answered,
        isFalse,
        reason: 'there was nothing of the node to give up, and a root node '
            'does not go looking outside itself',
      );
      expect(
        find.text('node content'),
        findsOneWidget,
        reason: "the route the node stands on is not the node's to give up",
      );
    });

    // The one guard of the public `PreviousNavigatorExtension`, and it had no
    // test: the walk starts from a context, and a caller that kept a
    // `NavigatorState` past the life of its tree gets one that is gone. A
    // public getter answers that rather than throwing out of an ancestor walk.
    testWidgets('previous answers null for a navigator whose tree is gone',
        (tester) async {
      final key = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(_RootNodeKeyHost(navigatorKey: key));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final navigator = key.currentState!;
      expect(navigator.previous, isNotNull, reason: 'control: there is one');

      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        navigator.previous,
        isNull,
        reason: 'and nothing is thrown at a caller for holding on to it',
      );
    });

    testWidgets('system back respects a guarded route inside the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open guarded'));
      await tester.pumpAndSettle();
      expect(find.text('guarded route'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('guarded route'), findsOneWidget);
    });

    testWidgets('system back stays in a root node while it has an inner route',
        (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true, isRoot: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed: secret'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('pushed: secret'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
        'system back asks onPop once when the node has nothing to '
        'close', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            // A circuit breaker, not part of the contract: a node that keeps
            // asking would otherwise hang the test instead of failing it.
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        1,
        reason: 'one system back is one question to onPop',
      );
    });

    testWidgets('an onPop that refuses keeps the outer route', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'onPop returned false, so the route it guards must stay',
      );
    });

    testWidgets('an onPop that allows the pop lets the outer route go', (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the screen that pushed the node is back on top',
      );
    });

    // Every test above pushes the node as a second route, so the pop it
    // forwards always has a route to take. On the first route of the
    // application there is none, and the navigator above must be left alone
    // rather than emptied.
    testWidgets('an ordinary node on the first route keeps the application',
        (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _FirstRouteNodeHost(
          onPop: (context, result) {
            calls++;

            return true;
          },
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1, reason: 'the hook is asked here as anywhere else');
      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'there is nothing outside the node to let the pop through to, '
            'and taking the only route of the application navigator leaves a '
            'blank screen',
      );
    });

    // An application may guard the route it puts a node on — "are you sure you
    // want to leave this screen". A node hands a pop over; it does not take
    // one, and a guard on the way out is not the node's to overrule.
    testWidgets('an application PopScope over the node keeps its route', (
      tester,
    ) async {
      var refusals = 0;

      await tester.pumpWidget(_AppGuardedHost(onRefused: () => refusals++));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'the application refused the pop, and the node was handing it '
            'over rather than taking it',
      );
      expect(
        refusals,
        1,
        reason: 'and the application hears one press as one: the node asks the '
            'route what a pop would do, which tells nobody anything, where a '
            'maybePop of its own would report a second refusal',
      );
    });

    testWidgets('the only page of a node can guard itself', (tester) async {
      await tester.pumpWidget(const _InnerGuardedHost());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: "a PopScope on the node's own page is inside the node, and "
            'the node asks its navigator before it decides anything outside',
      );
    });

    // The two parameters had never been used together. `isRoot` says the node
    // keeps a pop to itself, and `pop()` honours that; the system back path
    // reaches the navigator above by a different line, and nothing checked
    // that the same promise holds there.
    testWidgets('a root node keeps the pop even when onPop allows it',
        (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          isRoot: true,
          onPop: (context, result) {
            calls++;

            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1, reason: 'the hook is still asked');
      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'a root node keeps a pop to itself, and an onPop that allows '
            'one answers about the node, not about the route below it',
      );
    });

    // The answer reaches the same decision by the other branch, and the
    // asynchronous one is where the route is popped a whole turn of the event
    // loop after the press.
    testWidgets(
        'a root node keeps the pop when an asynchronous onPop allows it',
        (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          isRoot: true,
          onPop: (context, result) async {
            calls++;

            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('node content'), findsOneWidget);
    });

    testWidgets(
        'system back still reaches onPop after an inner route came '
        'and went', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Moving the inner stack makes the nested navigator report itself anew,
      // and the forwarding marker must not colour that report.
      await tester.tap(find.text('open inside'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('close inside'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        1,
        reason: 'the node has nothing of its own left to close, so the back '
            'belongs to onPop',
      );
      expect(find.text('node content'), findsOneWidget);
    });

    testWidgets('system back inside nested nodes keeps the enclosing route', (
      tester,
    ) async {
      await tester.pumpWidget(const _NestedHost());

      await tester.tap(find.text('open inner'));
      await tester.pumpAndSettle();
      expect(find.text('inner pushed'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('inner pushed'), findsNothing);
      expect(
        find.text('open inner'),
        findsOneWidget,
        reason: 'the innermost node handled the back; nothing above it moved',
      );
    });

    testWidgets('pop() on the only page of a root node keeps the page', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true, isRoot: true));
      expect(find.text('open'), findsOneWidget);

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'a root node keeps a pop to itself instead of emptying itself',
      );
    });

    testWidgets(
        'an ordinary node keeps its page when there is nowhere to '
        'forward a pop', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      // The node sits on the first route of the app, so the forwarded pop has
      // nothing to close. Doing it twice is the point: the way outwards must
      // not be a one-shot.
      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'the node must never be left with an empty stack',
      );
    });

    // The point of the node is that what it opens stands below the scopes the
    // node stands under. `onPop` is where the topic sends a reader to ask a
    // confirmation, and which navigator that confirmation lands on is decided
    // by the context the hook is handed.
    testWidgets('a dialog asked for by onPop belongs to the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _DialogOnPopHost());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('asking: secret'),
        findsOneWidget,
        reason: 'the dialog was opened with useRootNavigator: false, so it '
            'belongs to the node and reads the scope the node stands under',
      );

      await tester.tap(find.text('stay'));
      await tester.pumpAndSettle();
    });

    testWidgets('an ordinary node forwards a pop it cannot handle', (
      tester,
    ) async {
      await tester.pumpWidget(const _OnPopHost());
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the pop left the node and closed the route around it',
      );
    });

    testWidgets('a root node does not forward a pop even when it could', (
      tester,
    ) async {
      await tester.pumpWidget(const _OnPopHost(isRoot: true));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'there is a navigator above to forward to, and isRoot is '
            'exactly the instruction not to use it',
      );
    });

    testWidgets('the navigatorKey hands the nested navigator to its owner', (
      tester,
    ) async {
      final key = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(_Host(useNode: true, navigatorKey: key));

      expect(key.currentState, isNotNull);

      // Not awaited: the future a push returns completes when the route is
      // *popped*, so awaiting it here would wait for a screen nobody closes.
      unawaited(
        key.currentState!.push<void>(
          MaterialPageRoute<void>(builder: (context) => const _Pushed()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('pushed: secret'),
        findsOneWidget,
        reason: 'a route pushed through the key lands in the same node',
      );
    });

    // `NavigatorState.didUpdateWidget` compares the page list it is handed by
    // identity. A fresh list on every build therefore makes the nested
    // navigator diff its stack and report it again -- for a page that has not
    // changed at all -- and every listener above the node hears about it.
    testWidgets('a rebuild of the node hands its navigator the same pages',
        (tester) async {
      await tester.pumpWidget(const _RebuildableNodeHost());
      await tester.pumpAndSettle();

      final pagesBefore = _nodePages(tester);
      final reportsBefore = _RebuildableNodeHostState.instance!.reports;

      _RebuildableNodeHostState.instance!.rebuild();
      await tester.pumpAndSettle();

      expect(
        _nodePages(tester),
        same(pagesBefore),
        reason: 'the child is the same object, so there is nothing new to hand '
            'over',
      );
      expect(
        _RebuildableNodeHostState.instance!.reports,
        reportsBefore,
        reason: 'and the navigator therefore says nothing about its stack',
      );
    });

    testWidgets('a changed child hands its navigator a new page',
        (tester) async {
      await tester.pumpWidget(const _RebuildableNodeHost());
      await tester.pumpAndSettle();

      final pagesBefore = _nodePages(tester);

      _RebuildableNodeHostState.instance!.showOtherChild();
      await tester.pumpAndSettle();

      expect(_nodePages(tester), isNot(same(pagesBefore)));
      expect(
        find.text('the other child'),
        findsOneWidget,
        reason: 'keeping the list must not mean keeping a stale page',
      );
    });

    // An `onPop` that asks before answering leaves a window open, and the
    // system back does not wait politely. A second press used to start a
    // second question, and two `true` answers took two outer routes.
    testWidgets('an asynchronous onPop is asked once, however fast the presses',
        (tester) async {
      final gate = Completer<bool>();
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;

            return gate.future;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(calls, 1, reason: 'the second press met a question already asked');

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'and the answer took exactly one route',
      );
    });

    testWidgets('an asynchronous onPop that answers too late takes nothing',
        (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _OnPopHost(onPop: (context, result) => gate.future),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      // The route the node sits on is closed by something else while the
      // question is still open.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(find.text('go'), findsOneWidget);

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'an answer about a route that is already gone is not acted on',
      );
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'and it does not take the screen below with it',
      );
    });

    // The node is still mounted here -- its route only moved down the stack --
    // so `mounted` says nothing and the route itself has to be asked.
    testWidgets(
        'an asynchronous onPop answering under a newer route takes '
        'nothing', (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _OnPopHost(onPop: (context, result) => gate.future),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      // Something else pushes over the node while the question is open.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (context) => const Scaffold(body: Text('on top')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        find.text('on top'),
        findsOneWidget,
        reason: 'the answer was about a route that is no longer the top one',
      );
    });

    // A confirmation dialog is user code, and user code falls over. The chain
    // the answer travels in belongs to nobody, so a failure left in it
    // surfaced far from the widget that raised it -- as an unhandled zone
    // error, in whatever test or frame happened to be running.
    testWidgets('an asynchronous onPop that fails is reported', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;

            return Future<bool>.error(StateError('the dialog fell over'));
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(
        find.text('go'),
        findsNothing,
        reason: 'a question without an answer takes no route',
      );

      // And the node is not left thinking a question is still open.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(tester.takeException(), isA<StateError>());
    });

    // The report says which library it came from, and that name is read by
    // whoever collects errors from a running application. It said `scopo`
    // until this package left that one.
    testWidgets('a report from the node names this package', (tester) async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      // Passed on rather than swallowed: the binding is what records an error
      // for `takeException`, and a test that keeps one to itself leaves the
      // suite waiting for a frame that never settles.
      FlutterError.onError = (details) {
        reported.add(details);
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) =>
              Future<bool>.error(StateError('the dialog fell over')),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(reported, hasLength(1));
      expect(reported.single.library, 'navigation_node');
    });

    // The other half of the same chain: the question answered, and what the
    // answer sets off falls over. `then(onValue, onError:)` hands `onError` the
    // failures of the future it is chained to and nothing else, so a raise
    // inside `onValue` -- where the node asks the route about a pop, and where
    // it pops -- went to a chain nobody holds.
    testWidgets('a guard that raises while the node stands aside is reported',
        (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _RaisingGuardHost(onPop: (context, result) => gate.future.then(_arm)),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'asking the route is user code like any other: reported, not '
            'left in a chain nobody holds',
      );
    });

    // And the node does not keep standing aside. It steps aside for the length
    // of one read -- a raise in the middle of that read used to leave it aside
    // for good, and the node then let every later press take the whole route.
    testWidgets('a guard that raises does not leave the node stood aside',
        (tester) async {
      final gate = Completer<bool>();
      var calls = 0;

      await tester.pumpWidget(
        _RaisingGuardHost(
          onPop: (context, result) {
            calls++;

            return gate.future.then(_arm);
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        2,
        reason: "the press is still the node's to answer -- a node left stood "
            'aside is not asked at all, and the route simply goes',
      );
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'and this time the route went because the node said so',
      );
    });

    // The node can go without its route going: an app that swaps it out of the
    // route's subtree while a confirmation is on screen leaves the answer with
    // nothing to act through.
    testWidgets(
        'an asynchronous onPop answering after the node is gone takes '
        'nothing', (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _RemovableNodeHost(onPop: (context, result) => gate.future),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      _RemovableNodeState.instance!.removeNode();
      await tester.pumpAndSettle();

      expect(find.text('without a node'), findsOneWidget);

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('without a node'),
        findsOneWidget,
        reason: 'the answer had nothing left to pop through',
      );
    });

    // The key is what the navigator is built with, so a new one would mean a
    // new navigator and an empty stack. Refusing is the only honest answer --
    // and it is what catches a `GlobalKey()` built inline in `build`.
    testWidgets('a changed navigatorKey is refused', (tester) async {
      final first = GlobalKey<NodeNavigatorState>();
      final second = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(_Host(useNode: true, navigatorKey: first));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_Host(useNode: true, navigatorKey: second));

      expect(
        tester.takeException(),
        isA<AssertionError>().having(
          (error) => error.message.toString(),
          'message',
          contains('`Widget.key`'),
        ),
      );
    });

    testWidgets('a node route is not on the root navigator', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final rootNavigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      expect(
        rootNavigator.canPop(),
        isFalse,
        reason: 'the root navigator still holds a single route',
      );
    });

    // `popUntil` walks the stack by popping and looking at what is left on
    // top, and it ends when the predicate matches what it finds there. A node
    // whose `pop` takes nothing once its own page is all that is left leaves
    // that walk looking at the same route for ever -- a synchronous loop in the
    // frame it was called from. The predicate below counts and gives itself an
    // way out, because the alternative to giving up is a test that never ends.
    testWidgets('popUntil stops at the page of the node', (tester) async {
      final key = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(
        _Host(useNode: true, isRoot: true, navigatorKey: key),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      var asked = 0;
      key.currentState!.popUntil((route) {
        asked++;

        return asked > 20;
      });
      await tester.pumpAndSettle();

      expect(
        asked,
        lessThan(20),
        reason: 'a predicate that matches nothing inside the node must end on '
            'the page of the node rather than spin',
      );
      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'and what it ends on is that page, still there',
      );
    });

    // The hook may answer straight away, and one that raises there raises into
    // the loop [ModalRoute.onPopInvokedWithResult] runs over the entries of the
    // route -- so a `PopScope` of the application registered beside the node is
    // never called, and the failure reaches the application as a broken
    // platform message. Held and reported, the way an answer that falls over
    // later is.
    testWidgets('an onPop that raises straight away is reported', (
      tester,
    ) async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        reported.add(details);
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) => throw StateError('the hook fell over'),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(reported, hasLength(1));
      expect(reported.single.library, 'navigation_node');
      expect(
        find.text('go'),
        findsNothing,
        reason: 'a press that raised is simply not acted on',
      );
    });

    // The same for the other half of the synchronous path: the hook allows the
    // pop, and the guard the node reads on its way out is what falls over.
    testWidgets('a guard that raises for a straight answer is reported', (
      tester,
    ) async {
      await tester.pumpWidget(
        _RaisingGuardHost(
          onPop: (context, result) {
            _RaisingGuardState.instance!.armOnce();

            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'asking the route is user code like any other, and a straight '
            'answer is held no less than a late one',
      );
      expect(find.text('go'), findsNothing);
    });

    // And the third way out of the node: the pop handed to the navigator above
    // by `pop` on the node's first page. It runs the guards of the route up
    // there, and it used to run them into a future nobody held.
    testWidgets('a raise while handing a pop over is reported', (tester) async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        reported.add(details);
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(
        _RaisingGuardHost(onPop: (context, result) => true),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      _RaisingGuardState.instance!.armOnce();
      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(
        reported.map((details) => details.library),
        ['navigation_node'],
        reason: 'the failure belongs to the handover, and the handover is the '
            "node's",
      );
    });

    // What a node hears from its own subtree is news about a stack the
    // application has just told it to stay out of. Let past, it reaches
    // `WidgetsApp`, which tells the platform the framework handles back -- and
    // the predictive back gesture is then spent on a stack nobody can see.
    testWidgets('a switched-off node keeps what it hears to itself', (
      tester,
    ) async {
      final key = GlobalKey<NodeNavigatorState>();
      final heard = <bool>[];

      await tester.pumpWidget(
        _NotificationHost(enabled: false, navigatorKey: key, heard: heard),
      );
      await tester.pumpAndSettle();
      heard.clear();

      unawaited(
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (context) =>
                const Scaffold(body: Center(child: Text('hidden'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        heard,
        isEmpty,
        reason: 'a node with no place on the route has nothing to announce '
            'about a stack it has promised not to touch',
      );
    });

    testWidgets('control: a node on duty lets the same news past', (
      tester,
    ) async {
      final key = GlobalKey<NodeNavigatorState>();
      final heard = <bool>[];

      await tester.pumpWidget(
        _NotificationHost(enabled: true, navigatorKey: key, heard: heard),
      );
      await tester.pumpAndSettle();
      heard.clear();

      unawaited(
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (context) =>
                const Scaffold(body: Center(child: Text('shown'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        heard,
        contains(true),
        reason: 'a node that does stand on the route says so, and the '
            'framework needs to hear it',
      );
    });

    // A question outlives the moment it was asked, and the application may
    // answer a different one in between: switching the node off says it no
    // longer stands on that route, and an answer arriving afterwards would
    // take a route from a place the node has given up.
    testWidgets(
        'an answer arriving after the node is switched off takes '
        'nothing', (tester) async {
      final gate = Completer<bool>();
      final enabled = ValueNotifier<bool>(true);
      addTearDown(enabled.dispose);

      await tester.pumpWidget(
        _SwitchableNodeHost(
          enabled: enabled,
          onPop: (context, result) => gate.future,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      enabled.value = false;
      await tester.pump();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        find.text('go'),
        findsNothing,
        reason: 'the route stayed: the node that was asked about it is no '
            'longer standing there',
      );
      expect(find.text('node content'), findsOneWidget);
    });

    // A `Navigator` of the application's own, deeper than the node's, announces
    // that it can handle a pop -- and the node's navigator knows nothing about
    // it. The node handed the press to its own navigator all the same, which
    // had nothing of its own to give up and said so into a future nobody read:
    // the press reached neither the hook nor the route above, and vanished.
    testWidgets('a press nobody below took is still the node to answer', (
      tester,
    ) async {
      var asked = 0;

      await tester.pumpWidget(
        _InnerNavigatorHost(
          onPop: (context, result) {
            asked++;

            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('deeper please'));
      await tester.pumpAndSettle();
      expect(find.text('deeper'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        asked,
        1,
        reason: 'nothing below took the press, so it is the node that answers '
            'for it',
      );
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'and the route the node stands on went, the way it would have '
            'gone with no node there at all',
      );
    });
  });
}

final class _Config {
  final String value;

  const _Config(this.value);
}

/// Something a host puts over its subtree for a pushed route to find.
///
/// A plain [InheritedWidget]: what these tests ask is *where* a route is
/// built, and the cheapest answer to that is a lookup which succeeds only
/// below the host. [BuildContext.getInheritedWidgetOfExactType] reads without
/// subscribing — the value never changes here, and a dependency would only
/// add a rebuild to reason about.
final class _ConfigScope extends InheritedWidget {
  final _Config config;

  const _ConfigScope({required this.config, required super.child});

  static _Config? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ConfigScope>()?.config;

  @override
  bool updateShouldNotify(_ConfigScope oldWidget) => false;
}

final class _Host extends StatelessWidget {
  final bool useNode;
  final GlobalKey<NodeNavigatorState>? navigatorKey;
  final bool isRoot;

  const _Host({
    required this.useNode,
    this.navigatorKey,
    this.isRoot = false,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: _ConfigScope(
          config: const _Config('secret'),
          child: useNode
              ? NavigationNode(
                  navigatorKey: navigatorKey,
                  isRoot: isRoot,
                  child: const _NodeContent(),
                )
              : const _NodeContent(),
        ),
      );
}

final class _NodeContent extends StatelessWidget {
  const _NodeContent();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: Navigator.of(context).pop,
                child: const Text('pop the node'),
              ),
              TextButton(
                // The future a push returns completes when the route is popped,
                // and nothing here waits for that.
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const _Pushed(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  showDialog<void>(
                    context: context,
                    useRootNavigator: false,
                    builder: (context) => const AlertDialog(
                      content: Text('dialog'),
                    ),
                  ),
                ),
                child: const Text('open dialog'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const _GuardedPushed(),
                    ),
                  ),
                ),
                child: const Text('open guarded'),
              ),
            ],
          ),
        ),
      );
}

/// Puts a node with an [NavigationNode.onPop] on a route of its own, so a pop
/// that leaves the node has somewhere to land.
final class _OnPopHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;
  final bool isRoot;

  const _OnPopHost({this.onPop, this.isRoot = false});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => NavigationNode(
                        onPop: onPop,
                        isRoot: isRoot,
                        child: const _OnPopNodeContent(),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// The application guards the route it puts the node on, and refuses.
final class _AppGuardedHost extends StatelessWidget {
  final VoidCallback onRefused;

  const _AppGuardedHost({required this.onRefused});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => PopScope<void>(
                        canPop: false,
                        onPopInvokedWithResult: (didPop, result) {
                          if (!didPop) onRefused();
                        },
                        child: NavigationNode(
                          onPop: (context, result) => true,
                          child: const _OnPopNodeContent(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// The node's only page refuses the pop itself.
final class _InnerGuardedHost extends StatelessWidget {
  const _InnerGuardedHost();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: NavigationNode(
          child: PopScope<void>(canPop: false, child: _OnPopNodeContent()),
        ),
      );
}

/// A node under a scope, whose `onPop` asks a confirmation the way the `utils`
/// topic recommends asking one.
final class _DialogOnPopHost extends StatelessWidget {
  const _DialogOnPopHost();

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: _ConfigScope(
          config: const _Config('secret'),
          child: NavigationNode(
            onPop: (context, result) async {
              await showDialog<void>(
                context: context,
                useRootNavigator: false,
                builder: (context) {
                  final config = _ConfigScope.maybeOf(context);

                  return AlertDialog(
                    content: Text('asking: ${config?.value ?? 'none'}'),
                    actions: [
                      TextButton(
                        onPressed: Navigator.of(context).pop,
                        child: const Text('stay'),
                      ),
                    ],
                  );
                },
              );

              return false;
            },
            child: const _NodeContent(),
          ),
        ),
      );
}

/// Puts a node whose first page carries an `AppBar` on a pushed route, so the
/// arrow that `AppBar` draws has somewhere to go.
final class _AppBarHost extends StatelessWidget {
  final bool isRoot;

  const _AppBarHost({this.isRoot = false});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => NavigationNode(
                        isRoot: isRoot,
                        child: Scaffold(
                          appBar: AppBar(title: const Text('node content')),
                          body: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// Puts a `Scaffold` with a drawer on a pushed route, with or without a node
/// around it, so the two can be compared on the same press.
final class _DrawerHost extends StatelessWidget {
  final bool useNode;

  const _DrawerHost({required this.useNode});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => useNode
                          ? const NavigationNode(child: _DrawerScreen())
                          : const _DrawerScreen(),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

final class _DrawerScreen extends StatelessWidget {
  const _DrawerScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('node content')),
        drawer: const Drawer(child: Center(child: Text('drawer'))),
        body: const SizedBox.shrink(),
      );
}

/// A root node reachable by its `navigatorKey`, so the two paths out of it —
/// `pop` and `maybePop` — can be driven by hand.
final class _RootNodeKeyHost extends StatelessWidget {
  final GlobalKey<NodeNavigatorState> navigatorKey;

  const _RootNodeKeyHost({required this.navigatorKey});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => NavigationNode(
                        navigatorKey: navigatorKey,
                        isRoot: true,
                        child: const Text('node content'),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// Two nodes on one route, one per branch of an `IndexedStack` — the shape that
/// keeps the branch it does not show mounted and registered.
final class _TabbedNodesHost extends StatefulWidget {
  /// Whether the nodes are told which of them is on screen.
  final bool useEnabled;

  const _TabbedNodesHost({required this.useEnabled});

  @override
  State<_TabbedNodesHost> createState() => _TabbedNodesHostState();
}

final class _TabbedNodesHostState extends State<_TabbedNodesHost> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: IndexedStack(
            index: _tab,
            children: [
              for (var i = 0; i < 2; i++)
                NavigationNode(
                  enabled: !widget.useEnabled || i == _tab,
                  child: _TabScreen(name: 'tab$i'),
                ),
            ],
          ),
          bottomNavigationBar: TextButton(
            onPressed: () => setState(() => _tab = 1 - _tab),
            child: const Text('switch'),
          ),
        ),
      );
}

final class _TabScreen extends StatelessWidget {
  final String name;

  const _TabScreen({required this.name});

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Center(child: Text('$name inner')),
              ),
            ),
          ),
          child: Text('push $name'),
        ),
      );
}

/// Puts the `Scaffold` that owns the drawer *above* the node, on the same
/// pushed route, so the drawer's local history entry belongs to the route the
/// node stands on rather than to one inside it.
final class _DrawerAboveNodeHost extends StatelessWidget {
  final List<String> log;

  const _DrawerAboveNodeHost({required this.log});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('node content')),
                        drawer:
                            const Drawer(child: Center(child: Text('drawer'))),
                        body: NavigationNode(
                          onPop: (context, result) {
                            log.add('onPop');

                            return false;
                          },
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// Puts an ordinary node straight on the first route of the application, where
/// a pop that leaves the node has nowhere to land.
final class _FirstRouteNodeHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;

  const _FirstRouteNodeHost({this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NavigationNode(onPop: onPop, child: const _OnPopNodeContent()),
      );
}

/// A pushed route with a guard of its own that can be made to raise.
///
/// The guard is a [PopEntry], the same thing a `PopScope` registers and the same
/// thing the node registers, and it is read at the moment the route is asked
/// what a pop there would do. The node asks that question itself, from inside
/// the `then` of an asynchronous `onPop` -- so an armed guard raises exactly
/// where the failure the finding is about belongs.
///
/// Armed on demand rather than always: the first press reaches the same guard
/// through the outer navigator's own `maybePop`, and raising there would be the
/// application's callback failing on its own, with no chain of the node's in
/// sight.
final class _RaisingGuardHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result) onPop;

  const _RaisingGuardHost({required this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => _RaisingGuard(
                        child: NavigationNode(
                          onPop: onPop,
                          child: const _OnPopNodeContent(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// Arms the guard as the answer to `onPop` arrives.
///
/// Between this and the node's own read of the route there is nothing but a
/// microtask, so the read that raises is the node's.
bool _arm(bool answer) {
  _RaisingGuardState.instance!.armOnce();

  return answer;
}

/// Registers a [PopEntry] of its own on the route it is built in.
///
/// The same three lines the node's own dispatcher uses, so the guard is asked
/// whenever the route is: [ModalRoute.popDisposition] reads every entry it
/// holds.
final class _RaisingGuard extends StatefulWidget {
  final Widget child;

  const _RaisingGuard({required this.child});

  @override
  State<_RaisingGuard> createState() => _RaisingGuardState();
}

final class _RaisingGuardState extends State<_RaisingGuard>
    implements PopEntry<Object?> {
  static _RaisingGuardState? instance;

  ModalRoute<dynamic>? _route;

  @override
  final _RaisingCanPop canPopNotifier = _RaisingCanPop();

  bool _armedOnce = false;

  /// Arms the guard for the first answer only.
  ///
  /// A later press is answered the same way and would arm it again, and the
  /// point of the second press is what the node does when nothing is wrong.
  void armOnce() {
    if (_armedOnce) {
      return;
    }

    _armedOnce = true;
    canPopNotifier.armed = true;
  }

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _route?.unregisterPopEntry(this);
      _route = nextRoute;
      _route?.registerPopEntry(this);
    }
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(this);
    _route = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Answers `true`, and raises once when armed.
///
/// One shot on purpose: the route is asked what a pop would do from more places
/// than the node's own chain -- the framework asks whenever a navigator's
/// history changes -- and a guard that kept raising would report from all of
/// them. Armed from inside the answer to `onPop`, disarmed by the read itself,
/// it raises in exactly the read the node makes.
///
/// Not a `ValueNotifier`: it never changes its mind, it changes what reading it
/// does. The framework listens to it, so the listener methods are real methods
/// that do nothing rather than throwing ones.
final class _RaisingCanPop implements ValueListenable<bool> {
  bool armed = false;

  @override
  bool get value {
    if (!armed) {
      return true;
    }

    armed = false;

    throw StateError('the guard fell over');
  }

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// A pushed route whose subtree can drop the node while the route stays.
final class _RemovableNodeHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result) onPop;

  const _RemovableNodeHost({required this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => _RemovableNode(onPop: onPop),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

final class _RemovableNode extends StatefulWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result) onPop;

  const _RemovableNode({required this.onPop});

  @override
  State<_RemovableNode> createState() => _RemovableNodeState();
}

final class _RemovableNodeState extends State<_RemovableNode> {
  static _RemovableNodeState? instance;

  bool _hasNode = true;

  void removeNode() => setState(() => _hasNode = false);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  Widget build(BuildContext context) => _hasNode
      ? NavigationNode(
          onPop: widget.onPop,
          child: const _OnPopNodeContent(),
        )
      : const Scaffold(body: Center(child: Text('without a node')));
}

final class _OnPopNodeContent extends StatelessWidget {
  const _OnPopNodeContent();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('node content'),
              TextButton(
                onPressed: Navigator.of(context).pop,
                child: const Text('pop the node'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: Navigator.of(context).pop,
                            child: const Text('close inside'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open inside'),
              ),
            ],
          ),
        ),
      );
}

/// A node inside another node: the inner one is the only one with a route of
/// its own to close.
final class _NestedHost extends StatelessWidget {
  const _NestedHost();

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NavigationNode(
          isRoot: true,
          child: NavigationNode(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const Scaffold(
                            body: Center(child: Text('inner pushed')),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('open inner'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

final class _Pushed extends StatelessWidget {
  const _Pushed();

  @override
  Widget build(BuildContext context) {
    final config = _ConfigScope.maybeOf(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('pushed: ${config?.value ?? 'none'}'),
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('back'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _GuardedPushed extends StatelessWidget {
  const _GuardedPushed();

  @override
  Widget build(BuildContext context) => const PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(child: Text('guarded route')),
        ),
      );
}

/// The pages the node's own navigator is holding.
///
/// `find.byType` matches an exact runtime type, and the node builds a private
/// subclass of `Navigator`, so the navigators are found by predicate: the outer
/// one is the ancestor, the node's is the last.
List<Page<Object?>> _nodePages(WidgetTester tester) => tester
    .stateList<NavigatorState>(
      find.byWidgetPredicate((widget) => widget is Navigator),
    )
    .last
    .widget
    .pages;

/// A node under a parent that can rebuild without changing anything.
///
/// The child is `const`, so it is the same object on every build -- which is
/// what a node has to notice. Also counts what the nested navigator says about
/// its stack: a `NavigationNotification` is dispatched whenever a navigator's
/// history is flushed, which is what a needless page diff ends in.
final class _RebuildableNodeHost extends StatefulWidget {
  const _RebuildableNodeHost();

  @override
  State<_RebuildableNodeHost> createState() => _RebuildableNodeHostState();
}

final class _RebuildableNodeHostState extends State<_RebuildableNodeHost> {
  static _RebuildableNodeHostState? instance;

  bool _other = false;

  int reports = 0;

  void rebuild() => setState(() {});

  void showOtherChild() => setState(() => _other = true);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NotificationListener<NavigationNotification>(
          onNotification: (notification) {
            reports++;

            return false;
          },
          child: NavigationNode(
            child: _other
                ? const Scaffold(body: Center(child: Text('the other child')))
                : const Scaffold(body: Center(child: Text('the first child'))),
          ),
        ),
      );
}

/// A plain `Navigator` inside the node — one the node's own navigator knows
/// nothing about, and which announces that it can handle a pop as soon as it
/// has a route of its own to give up.
final class _InnerNavigatorHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;

  const _InnerNavigatorHost({this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => NavigationNode(
                        onPop: onPop,
                        child: const _InnerNavigator(),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

final class _InnerNavigator extends StatelessWidget {
  const _InnerNavigator();

  @override
  Widget build(BuildContext context) => Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const Scaffold(
                        body: Center(child: Text('deeper')),
                      ),
                    ),
                  ),
                ),
                child: const Text('deeper please'),
              ),
            ),
          ),
        ),
      );
}

/// Listens for what a node lets past it, from just above the node.
///
/// The route the node stands on announces what it holds from its own subtree
/// context, which is above this listener — so what is heard here came from the
/// node and from nowhere else.
final class _NotificationHost extends StatelessWidget {
  final bool enabled;
  final GlobalKey<NodeNavigatorState> navigatorKey;
  final List<bool> heard;

  const _NotificationHost({
    required this.enabled,
    required this.navigatorKey,
    required this.heard,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NotificationListener<NavigationNotification>(
          onNotification: (notification) {
            heard.add(notification.canHandlePop);

            return false;
          },
          child: NavigationNode(
            enabled: enabled,
            navigatorKey: navigatorKey,
            child: const _OnPopNodeContent(),
          ),
        ),
      );
}

/// A node on a pushed route, whose `enabled` the test can switch while the node
/// is still deciding about a press.
final class _SwitchableNodeHost extends StatelessWidget {
  final ValueListenable<bool> enabled;
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;

  const _SwitchableNodeHost({required this.enabled, this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => ValueListenableBuilder<bool>(
                        valueListenable: enabled,
                        builder: (context, enabled, child) => NavigationNode(
                          enabled: enabled,
                          onPop: onPop,
                          child: const _OnPopNodeContent(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}
