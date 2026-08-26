import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A nested `Navigator` that keeps what it opens inside the screen it stands on.
///
/// A dialog, a bottom sheet or a pushed route opened through a node is built
/// below the node rather than above the whole application, so everything the
/// screen put over its own subtree is still among that route's ancestors. The
/// other half of the widget is the system back: a node is a [PopEntry] of the
/// route it stands on, so back closes what the node has open before it touches
/// the route around it. Named routes work inside a node and land inside it.
final class NavigationNode extends StatefulWidget {
  /// Whether this node is the outermost one.
  ///
  /// A root node keeps a pop to itself; any other node forwards a pop it
  /// cannot handle to the navigator above it.
  final bool isRoot;

  /// The subtree the nested navigator shows first.
  final Widget child;

  /// Gives access to the nested navigator from outside the node.
  ///
  /// Fixed for the lifetime of the node: it is the key the nested navigator is
  /// built with, so another one would mean another navigator and an empty
  /// stack. Handing over a different one is refused by an assertion — hold the
  /// key in a `State` field rather than writing `GlobalKey()` inside `build`.
  final GlobalKey<NodeNavigatorState>? navigatorKey;

  /// Answers a pop the route this node stands on is *asked* about.
  ///
  /// The system back is the usual one, and not the only one: the node is a
  /// [PopEntry] of that route, so everything that asks the route reaches here
  /// — `Navigator.maybePop()`, and the back arrow of an `AppBar` **above** the
  /// node as much as one inside it. What does not reach here is a
  /// `Navigator.pop()` of a route *inside* the node: it takes that route
  /// rather than asking it, and no [PopEntry] of any kind is consulted. On the
  /// node's first page there is no such route to take — the pop leaves the
  /// node instead, and leaving is asking the navigator above, whose route this
  /// node is a [PopEntry] of. The hook is reached there as well. A screen
  /// button that must go through this hook wants `maybePop`; one that must
  /// leave without being asked about wants
  /// `Navigator.of(context).previous?.pop()`.
  ///
  /// Return `true` to let the pop through, `false` to keep the route, or a
  /// [Future] to decide after asking — a confirmation dialog, usually. The
  /// `result` is what the popped route would have returned.
  ///
  /// The `context` is one from inside the node, so `Navigator.of(context)` is
  /// the nested navigator and a dialog opened with `useRootNavigator: false`
  /// belongs to the node — which is the point of asking here rather than
  /// anywhere else: what the node stands under is above that dialog too.
  ///
  /// A [Future] is asked for one press at a time: a back arriving while an
  /// answer is still pending is dropped rather than starting a second
  /// question. And an answer is acted on only while it still applies — if the
  /// route the node sits on has been closed by something else, or buried under
  /// a newer one, a `true` takes nothing, since a pop would otherwise take
  /// whatever is on top instead of what was asked about.
  ///
  /// Anything that falls over on the way — the hook itself, or a guard the
  /// application put on the route, which is read when the node asks what a pop
  /// there would do — is reported through `FlutterError.reportError` rather
  /// than left in a chain nobody holds, where it would surface as an unhandled
  /// zone error far from the widget that caused it. The press is simply not
  /// acted on, and the next one is asked as usual.
  ///
  /// On a root node the hook is asked as it is anywhere else, but `true` takes
  /// nothing there either: [isRoot] says the node keeps a pop to itself, and
  /// there is nothing outside it to let the pop through to. What such a hook is
  /// for is the press itself — a "press again to exit", or a call to
  /// `SystemNavigator.pop()` the application makes on its own terms.
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;

  /// Whether this node takes part in the system back of the route it stands on.
  ///
  /// `true` by default, and there is one shape where it has to be told
  /// otherwise: **several nodes on one route**, of which only one is on
  /// screen — a node per tab of an `IndexedStack`, which keeps the branches it
  /// does not show mounted. A route asks every one of its `PopEntry`s and
  /// calls every one of them back, so a single back press unwound the stack of
  /// every node on the route at once, the hidden ones included.
  ///
  /// Which node is the one on screen is not something a node can find out:
  /// `TickerMode` and `ModalRoute` read exactly the same in a hidden branch as
  /// in a shown one, and the order sibling nodes register in says nothing. The
  /// application knows, and this is where it says so:
  ///
  /// ```dart
  /// NavigationNode(
  ///   enabled: index == _currentTab,
  ///   child: TabScreen(),
  /// )
  /// ```
  ///
  /// A disabled node takes no place on the route at all — it is not asked, and
  /// it is not called back. Everything else about it goes on working: the
  /// nested navigator keeps its stack, and `Navigator.of(context)` from inside
  /// still pushes and pops there.
  ///
  /// Nodes nested one inside another never need this. An inner node registers
  /// on the page of the navigator above it rather than on the route both stand
  /// on, so two of them are never asked about the same press.
  ///
  /// The same ambiguity is Flutter's own: two `PopScope`s on one route are both
  /// consulted, and an application resolves it the same way.
  final bool enabled;

  /// The observers the node tells about the navigation inside it.
  ///
  /// A node hands its navigator one observer of its own and retells what it
  /// hears — to everything in this list first, and then, while
  /// [observedFromAbove], to the observers of the navigator above.
  ///
  /// Retelling rather than handing over is what makes the list work at all. A
  /// `NavigatorObserver` belongs to one navigator and one only: the framework
  /// writes the owner down when the navigator is built and asserts nothing was
  /// there before, so the `RouteObserver` of an application — bound to the
  /// navigator of the application — cannot be handed to a node as well.
  /// Retelling binds nothing and unbinds nothing, and one instance can
  /// therefore serve the navigator of the application and any number of nodes
  /// at the same time.
  ///
  /// The price is that `NavigatorObserver.navigator` says nothing about the
  /// node. It is `null` for an observer that is never anything but a delegate;
  /// it is the navigator of the application for one the application declared;
  /// and it is never the navigator whose navigation has just been retold. An
  /// observer that reads it is asking about somewhere else — `HeroController`
  /// is the framework's own, and it has no business in this list.
  ///
  /// An observer that already stands anywhere above does not belong here while
  /// [observedFromAbove]: it would be told twice, and a `RouteObserver` would
  /// wake its subscribers twice for one push. An assertion refuses that — the
  /// nodes between are walked through, so a name repeated further up the chain
  /// is refused as well — and it refuses one observer named twice in this list.
  /// The assertion is read when the node builds, which is the one thing it
  /// cannot promise about a list an application changes in place: such a
  /// duplicate is delivered twice until something rebuilds the node.
  ///
  /// A node inside a node inherits the audience of the navigator above it, and
  /// this list is part of that audience — so what is named here hears the nodes
  /// inside this one as well. The chain is made of nodes and nothing else: a
  /// plain nested `Navigator` between a node and the application has no proxy
  /// to pass anything on with.
  ///
  /// The page a node builds for itself is announced to nobody when the node
  /// mounts. It stands for the route the node stands on, which the navigator
  /// above has announced already, and announcing it again would give an
  /// application two screens where it has one, the second of them nameless.
  /// Everything after that is passed on as it is, the events that name that
  /// page as their previous route included — which is what tells a `RouteAware`
  /// on the node's first page that something has covered it, through a
  /// `RouteObserver<PageRoute>` or wider, since the node builds a `PageRoute`
  /// and not a `MaterialPageRoute`. The page becoming the topmost one again is
  /// announced too, nameless as it is.
  ///
  /// Two things a node never says. It says nothing as it leaves the tree: a
  /// node taken off screen with a stack still inside it disposes those routes
  /// the way any nested navigator does, without a `didPop` or a `didRemove`
  /// for any of them, so an observer that counts what is open closes its own
  /// books when the route holding the node goes. And a `RouteAware` on the
  /// node's first page hears that the node covered it, never that the
  /// application did — the route it is subscribed to is the node's page, and
  /// what the application pushes goes on another navigator entirely.
  final List<NavigatorObserver> observers;

  /// Whether the navigation inside this node reaches the observers of the
  /// navigator above it.
  ///
  /// `true` by default, so a `RouteObserver`, an analytics observer or a
  /// logger the application has already declared sees what is pushed and
  /// popped inside a node the way it sees the rest of the application. What is
  /// inherited is the list that navigator was handed —
  /// `MaterialApp.navigatorObservers`, or the `observers` of whatever
  /// `Navigator` stands over the node.
  ///
  /// Nodes chain: for a node inside a node the navigator above is the outer
  /// node's, whose observer is the outer node's own, and the events travel out
  /// through it. This switch therefore cuts the chain where it is set `false`:
  /// the nodes inside such a node stop reaching the application, whatever they
  /// say for themselves. What they do not stop reaching is [observers] of that
  /// same node — an inner node inherits the whole audience of the navigator
  /// above, and the outer node's own list is part of it.
  ///
  /// Set it `false` for a node whose navigation is nobody else's business.
  /// [observers] still says who hears it then.
  final bool observedFromAbove;

  /// The identifier under which the stack inside this node is kept and
  /// restored.
  ///
  /// `null` by default, and then nothing inside the node survives the
  /// application being killed and brought back: it starts again from the
  /// node's own page. Given a name, the node's navigator keeps its stack in a
  /// `RestorationBucket` of that name, and its own page is entered in it as
  /// well — a route pushed imperatively is kept under the page it was pushed
  /// over, so without that the stack above it could not come back either.
  ///
  /// What comes back is what Flutter can build again without the code that
  /// pushed it: `restorablePush` and its neighbours, which keep a reference to
  /// a static builder and arguments that survive being written down. An
  /// ordinary `push` carries a closure and is never restored — that is the
  /// framework's rule and not the node's. The builder must be a top-level or
  /// static function annotated with `@pragma('vm:entry-point')`, since the
  /// navigator asks for it by name when it builds the route anew; without the
  /// annotation a test still passes and an application fails at the moment of
  /// restoring, with «To closurize … from native code, it must be annotated». `restorablePushNamed` works from
  /// inside a node like any other name: the route table is borrowed from the
  /// navigator above, and it is borrowed again when the name is built anew.
  ///
  /// The name has to be unique among everything that claims a bucket from the
  /// same scope — two nodes on one route need two names, and the framework
  /// says so with «Multiple owners claimed child RestorationBuckets with the
  /// same IDs» rather than quietly mixing the two. And none of it happens at
  /// all unless the application enables restoration for itself:
  /// `MaterialApp.restorationScopeId`, or a `RootRestorationScope` of its own.
  final String? restorationScopeId;

  /// Creates a navigation node around [child].
  const NavigationNode({
    super.key,
    this.navigatorKey,
    this.isRoot = false,
    this.onPop,
    this.enabled = true,
    this.observedFromAbove = true,
    this.observers = const [],
    this.restorationScopeId,
    required this.child,
  });

  @override
  State<NavigationNode> createState() => _NavigationNodeState();
}

final class _NavigationNodeState extends State<NavigationNode> {
  /// The key the node was given, kept apart from the one it uses: `null` is an
  /// answer like any other, and a node that is later handed a key has to be
  /// told the same thing as one that is handed a different key.
  late final GlobalKey<NodeNavigatorState>? _declaredKey = widget.navigatorKey;

  late final _navigatorKey = _declaredKey ?? GlobalKey<NodeNavigatorState>();

  /// Whether the node is standing aside while it asks the route it stands on
  /// what a pop there would do. Raised for the length of one read.
  bool _forwarding = false;

  /// Whether an [NavigationNode.onPop] is still deciding about a press.
  bool _deciding = false;

  /// The nested navigator, or `null` when the node is not on the tree.
  ///
  /// Nullable rather than `!`: a node that is gone answers for itself — its
  /// key resolves to nothing — and every other read of this key in the file is
  /// already written that way.
  NodeNavigatorState? get _navigator => _navigatorKey.currentState;

  /// What the nested navigator is told to report to, kept rather than rebuilt.
  ///
  /// One observer, the node's own, and always the same instance: the framework
  /// binds an observer to the navigator it was handed to, and
  /// [NavigatorState.didUpdateWidget] compares this list by identity — a fresh
  /// one on every build would unbind and rebind it every time. Nothing is lost
  /// by keeping it, because [_NodeObserver] reads the list the node was given
  /// at the moment it retells something rather than remembering it.
  late final List<NavigatorObserver> _observers = [_NodeObserver(this)];

  /// The page list the nested navigator is handed, kept rather than rebuilt.
  ///
  /// [NavigatorState.didUpdateWidget] compares the list it was given by
  /// identity, so a fresh one on every build makes the navigator diff its stack
  /// and report it again for a page that has not changed. What the page is made
  /// of is [NavigationNode.child] and [NavigationNode.isRoot]; while those stay
  /// the same objects — a `const` subtree, or one an application holds in a
  /// field — a rebuild of the node hands over nothing new.
  late List<Page<void>> _pages = _buildPages();

  List<Page<void>> _buildPages() => [
        _NodePage(
          child: widget.child,
          leavesTheNode: !widget.isRoot,
          // Constant, and needed all the same. The bucket of this page lives
          // inside the bucket of the node's navigator, so there is nothing for
          // its name to collide with -- but a page with no name at all takes
          // no part in restoration, and the routes pushed over it are kept
          // under it. Without this the navigator's own identifier restores an
          // empty stack.
          restorationId:
              widget.restorationScopeId == null ? null : _nodePageRestorationId,
        ),
      ];

  /// The node's navigator never removes the node's own page, and the pages API
  /// asks for the callback all the same. A method rather than a closure in
  /// `build`, for the same reason [_pages] is a field.
  static void _onDidRemovePage(Page<Object?> page) {}

  @override
  void didUpdateWidget(NavigationNode oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(widget.child, oldWidget.child) ||
        widget.isRoot != oldWidget.isRoot ||
        (widget.restorationScopeId == null) !=
            (oldWidget.restorationScopeId == null)) {
      _pages = _buildPages();
    }
  }

  /// Whether nobody in the node's audience is named twice.
  ///
  /// Read by an assertion in [build] and nowhere else. Nothing in the framework
  /// catches this for us: a `Navigator` refuses a repeated observer only
  /// because it binds each one it is handed, and a delegate is bound to
  /// nothing — which is the whole reason a node can retell to the observers of
  /// the application at all.
  bool _audienceIsDistinct(NavigatorState? above) {
    final own = widget.observers;

    for (var i = 0; i < own.length; i++) {
      if (own.indexWhere((other) => identical(other, own[i]), i + 1) >= 0) {
        return false;
      }
    }

    if (!widget.observedFromAbove) {
      return true;
    }

    return !_audienceAbove(above).any(
      (inherited) => own.any((mine) => identical(mine, inherited)),
    );
  }

  /// Everyone a node standing here retells to, apart from its own list.
  ///
  /// Not the same thing as the observers the navigator above declares. When
  /// that navigator belongs to another node, what it declares is that node's
  /// own proxy, and the audience behind the proxy is the outer node's
  /// [NavigationNode.observers] and — while that node inherits in turn —
  /// whatever stands above it. Walking through the proxies is what makes the
  /// assertion in [build] mean what the documentation says it means: measured
  /// against the declared list alone, a duplicate anywhere in a chain of nodes
  /// went through without a word, which is exactly where it is hardest to spot
  /// by reading. Read from an assertion, so this walk costs a release build
  /// nothing.
  Iterable<NavigatorObserver> _audienceAbove(NavigatorState? above) sync* {
    if (above == null) {
      return;
    }

    final navigator = above.widget;
    if (navigator is! _NodeNavigator) {
      yield* navigator.observers;

      return;
    }

    final node = navigator.node;
    yield* node.widget.observers;

    if (node.widget.observedFromAbove && node.mounted) {
      yield* node._audienceAbove(Navigator.maybeOf(node.context));
    }
  }

  /// Whether the nested navigator has something of its own to close.
  ///
  /// Asked, never remembered. What it answers about is the local history of the
  /// route the node stands on as much as the stack above it — a `Drawer`, a
  /// bottom sheet, an `addLocalHistoryEntry` of the application's own — and
  /// none of those tell anybody they happened: `LocalHistoryRoute
  /// .addLocalHistoryEntry` ends in `changedInternalState`, which marks the
  /// route dirty and dispatches no notification. A remembered answer is
  /// therefore an answer from before the drawer opened.
  bool get _handlesBackInside => _navigator?.canPop() ?? false;

  /// Decides what a system back does once the node itself cannot answer it.
  ///
  /// Refusing takes no undoing: nothing has been spent to get here, so the next
  /// press arrives exactly as this one did.
  ///
  /// [dispatcher] is what stands on the route for the node, and the route it
  /// stands on is where a pop would land. Asked rather than looked up again:
  /// the two can part, and only one of them is right. A node that has been
  /// switched off has given its place up and holds no route at all, while a
  /// fresh lookup would still find the one the node is no longer standing on.
  ///
  /// What the hook is given is neither of those. It is a context from *inside*
  /// the node, so that a dialog opened with `useRootNavigator: false` belongs
  /// to the node rather than to the navigator of the application, above
  /// everything the node exists to stay below.
  void _decideOutside(_NodeBackDispatcherState dispatcher, Object? result) {
    // A decision already under way is the answer to this press too. Nothing
    // queues: a second back while a confirmation is on screen must not ask a
    // second time, and two answers of `true` must not take two routes.
    //
    // Whether there is a navigator above is *not* asked here, and used to be.
    // The hook is documented to be asked wherever the press reaches the node —
    // a root node included, where it is asked for the press itself and `true`
    // takes nothing — so refusing to ask it because there is nothing outside
    // to hand a pop to made the promise wider than the code. What the pop is
    // handed to is [_popOutside]'s question, and it asks it null-safely.
    final navigator = _navigator;
    if (_deciding || navigator == null) {
      return;
    }

    final route = dispatcher._route;

    final FutureOr<bool>? answer;
    try {
      // ignore: discarded_futures
      answer = widget.onPop?.call(navigator.context, result);
    } on Object catch (error, stackTrace) {
      // A hook that answers straight away is user code like any other, and it
      // raises into the loop [ModalRoute.onPopInvokedWithResult] runs over the
      // entries of the route -- taking the rest of that loop with it, so that
      // a `PopScope` of the application beside this node is never called, and
      // arriving at the application as a failed platform message. Reported
      // instead, the way an answer that falls over later is: the press is
      // simply not acted on.
      _reportBackFailure(error, stackTrace, _decidingBack);

      return;
    }

    switch (answer) {
      case final Future<bool> future:
        _deciding = true;

        // Anything in the chain below that falls over -- the question itself, a
        // confirmation dialog raising, or the pop, which runs user code of its
        // own as the route goes -- fails where nobody is waiting, and the
        // failure then surfaces as an unhandled zone error far from the widget
        // that caused it. Reported instead, the way the package reports
        // everything it cannot re-throw. The press is simply not acted on, and
        // `whenComplete` has already cleared the way for the next one.
        //
        // The handler is `onError` on the chain, not the `onError` of `then`:
        // that one answers for the future it is chained to and not for the
        // callback beside it, so the pop's own failures went unheld.
        unawaited(
          future.whenComplete(() => _deciding = false).then((canPop) {
            // The world does not wait for an answer. The route the node sits
            // on may have been closed by something else, or buried under a
            // newer one -- and a pop would then take whatever is on top
            // instead of what was asked about. The node itself may have been
            // switched off while the question was on screen, which gives up
            // its place on that route as surely as leaving the tree does.
            // [_NodeBackDispatcherState._stillOn] is all three questions.
            if (!canPop || !dispatcher._stillOn(route)) {
              return;
            }

            _popOutside(route, result);
          }).onError<Object>((error, stackTrace) {
            _reportBackFailure(error, stackTrace, _decidingBack);
          }),
        );
      case final bool? canPop:
        if (canPop ?? true) {
          try {
            _popOutside(route, result);
          } on Object catch (error, stackTrace) {
            // Reading the route means reading every guard on it, and a guard
            // that raises here raises where the asynchronous path would have
            // reported it. Same press, same answer.
            _reportBackFailure(error, stackTrace, _decidingBack);
          }
        }
    }
  }

  /// Hands the pop to the navigator above, unless this node is the outermost
  /// one.
  ///
  /// [NavigationNode.isRoot] says the node keeps a pop to itself, and
  /// [NodeNavigatorState.pop] has always honoured that. The system back arrives
  /// by this other path, where the promise held only for as long as nobody
  /// wrote an [NavigationNode.onPop]: a root node with one that allowed the pop
  /// took the route below it, and a root node placed as `home` took the last
  /// route of the application's own navigator and left a blank screen.
  ///
  /// The hook is still asked — it is where an application decides what its own
  /// outermost back means, and it may act on the press itself. What a root node
  /// no longer does is leave.
  ///
  /// Handing over is asking, not taking. [NavigatorState.pop] takes the last
  /// route it holds and asks nobody, so this used to walk past a [PopScope] the
  /// application had put around the node, and to empty the application's own
  /// navigator when the node stood on its first route — a blank screen, and an
  /// assertion of the framework on the frame after it. Asking [route] what a
  /// pop there would do settles both, and asking is all it does: reading
  /// [ModalRoute.popDisposition] dispatches nothing, where a `maybePop` would
  /// report a refusal of its own to every [PopScope] on that route.
  void _popOutside(ModalRoute<dynamic>? route, Object? result) {
    if (widget.isRoot) {
      return;
    }

    final previous = _navigator?.previous;
    if (previous == null || route == null) {
      return;
    }

    // The route is asked rather than told, and it is asked with the node's own
    // answer stood aside -- the node's entry is registered on this very route,
    // and it has already had its say. What is left is what the node has no
    // business answering for itself: a `PopScope` the application put around
    // the node, and whether there is a route to give up at all. `maybePop`
    // would ask the same question by telling the route the pop was refused,
    // and the application would then hear one press as two.
    final RoutePopDisposition disposition;

    _forwarding = true;
    try {
      disposition = route.popDisposition;
    } finally {
      // Stepping aside lasts one read, whatever that read does. Reading a route
      // means reading every guard on it, which is user code: one that falls over
      // used to leave the node aside for good, and every later press then took
      // the whole route without the node being asked at all.
      _forwarding = false;
    }

    if (disposition == RoutePopDisposition.pop) {
      previous.pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // In `build`, not in `didUpdateWidget`: a failure here is caught by
    // Flutter's build error boundary, while one raised from `didUpdateWidget`
    // abandons the update halfway and takes the frame down with it.
    assert(
      identical(widget.navigatorKey, _declaredKey),
      'The `navigatorKey` of a NavigationNode cannot change. It is the key the '
      'nested navigator is built with, so another one would mean another '
      'navigator and an empty stack -- which is why the node keeps the first '
      'one, and the new key simply never resolves. Give the widget a different '
      '`Widget.key` when a fresh navigator is what you want. If this fired on '
      'a `GlobalKey()` written inside `build`, hold it in a `State` field '
      'instead: that expression makes a new key on every rebuild.',
    );

    // The route table of the application, borrowed for the navigator inside.
    // A node is handed one page and nothing else, so a name pushed inside it
    // reached a navigator that had never heard of `routes:` and ended in an
    // assertion of the framework — while the application had declared its
    // routes in the one place there is to declare them. Asking the navigator
    // above for its own factory makes a name mean inside the node what it
    // means outside, and the route then lands below the node, which is what
    // pushing it there was for. Nested nodes chain: each borrows from the one
    // above, which borrowed from the one above that.
    //
    // Read here rather than through [PreviousNavigatorExtension.previous],
    // which walks up from the navigator inside — and that one does not exist
    // yet on the first build. Read on every build rather than remembered, and
    // nothing is subscribed to: `Navigator.maybeOf` walks ancestors instead.
    // That is enough, because what an application hands over is a method of
    // its own state that reads its `routes` as they are, so a table that
    // changes is followed without anybody rebuilding for it.
    //
    // This cannot give the node an initial route of its own. A navigator
    // generates one only when its page list is empty
    // ([NavigatorState.restoreState]), and this page list never is.
    final above = Navigator.maybeOf(context);

    assert(
      _audienceIsDistinct(above),
      'A NavigationNode was given an observer it is already telling. While '
      '`observedFromAbove` is true a node retells everything to the observers '
      'of the navigator above it, so naming one of those in `observers` as '
      'well has it told twice -- a RouteObserver then wakes its subscribers '
      'twice for one push, and a screen counter counts one screen as two. Take '
      'it out of `observers`, or set `observedFromAbove: false` if this node '
      'is to report to that list alone. The same goes for one observer named '
      'twice in `observers` itself.',
    );

    return _NodeBackDispatcher(
      node: this,
      child: _NodeNavigator(
        key: _navigatorKey,
        node: this,
        pages: _pages,
        observers: _observers,
        restorationScopeId: widget.restorationScopeId,
        onDidRemovePage: _onDidRemovePage,
        onGenerateRoute: above?.widget.onGenerateRoute,
        onUnknownRoute: above?.widget.onUnknownRoute,
      ),
    );
  }
}

/// Sends a system back to the navigator below before anything outside sees it.
///
/// It is a [PopEntry] of its own rather than a [PopScope] because the answer a
/// [PopScope] gives is the one its `canPop` had when it was last built, and the
/// question is asked at moments no build of this subtree is tied to. A drawer
/// opening inside the node is the plain case: the route the node stands on
/// gains a local history entry, nothing is dispatched and nothing rebuilds, and
/// a remembered `true` then lets the whole route go instead of closing the
/// drawer. A [PopEntry] is read at the moment [ModalRoute.popDisposition] asks,
/// which is when the node can still answer correctly.
///
/// It also lives in a widget of its own so that what it keeps never rebuilds
/// the nested navigator: a rebuild would hand that navigator a fresh page list,
/// which makes it report its stack again.
final class _NodeBackDispatcher extends StatefulWidget {
  final _NavigationNodeState node;
  final Widget child;

  const _NodeBackDispatcher({required this.node, required this.child});

  @override
  State<_NodeBackDispatcher> createState() => _NodeBackDispatcherState();
}

final class _NodeBackDispatcherState extends State<_NodeBackDispatcher>
    implements PopEntry<Object?> {
  /// Whether something below the node refuses a pop of its own accord.
  ///
  /// Kept from [NavigationNotification], which is dispatched when a nested
  /// navigator's stack changes and when a [PopScope] below registers or changes
  /// its answer — including navigators deeper than this node's own, so a node
  /// nested in another node is heard here too. This is the half the node cannot
  /// work out by asking its own navigator, and it is the half that does get
  /// announced.
  bool _innerCanPop = false;

  ModalRoute<dynamic>? _route;

  @override
  late final _NodeCanPopOutside canPopNotifier = _NodeCanPopOutside(this);

  /// Whether a system back arriving at the route this node stands on is none of
  /// the node's business.
  ///
  /// [ModalRoute.willHandlePopInternally] comes first, and it has to: a route
  /// asks its [PopEntry]s before it looks at its own local history, so an
  /// entry that says "do not pop" is the end of the matter — the drawer, the
  /// bottom sheet or the [LocalHistoryEntry] the application put there never
  /// gets the press. A node with an `onPop` said exactly that unconditionally,
  /// so a `Scaffold` with a `drawer:` above the node could not be closed with
  /// back at all, and the user was asked "leave this screen?" about a press
  /// whose whole job was to close a drawer.
  ///
  /// Read live rather than cached: the value is read at press time, and
  /// nothing announces a local history entry coming or going.
  bool get _canPopOutside =>
      widget.node._forwarding ||
      (_route?.willHandlePopInternally ?? false) ||
      (widget.node.widget.onPop == null &&
          !_innerCanPop &&
          !widget.node._handlesBackInside);

  /// Nothing, the way [PopEntry.onPopInvoked] is nothing.
  ///
  /// It is the deprecated half of the pair, replaced by
  /// [onPopInvokedWithResult], and the framework's own implementation is empty.
  /// Raising from it made this class refuse to be a `PopEntry` in any version
  /// of Flutter that still calls it — for a method the package has nothing to
  /// say through.
  @Deprecated('Use onPopInvokedWithResult instead')
  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop || widget.node._forwarding) {
      return;
    }

    final navigator = widget.node._navigator;
    if (navigator != null && (_innerCanPop || widget.node._handlesBackInside)) {
      _askInside(navigator, result);

      return;
    }

    widget.node._decideOutside(this, result);
  }

  /// Offers the press to the navigator below, and takes it back if nothing
  /// there wanted it.
  ///
  /// [_innerCanPop] is heard from the whole subtree, and a `Navigator` or a
  /// `Router` of the application's own, deeper than the node's, announces
  /// itself through it exactly as the node's own navigator does -- while the
  /// only navigator this node can hand a press to is its own. Offering is
  /// therefore a question and not a handover: [NodeNavigatorState._popInside]
  /// answers `true` when something below took the press -- a route of its own
  /// was given up, or a guard on the node's page refused and was told so --
  /// and `false` when nothing below did anything at all.
  ///
  /// That `false` used to be dropped along with the future carrying it, and the
  /// press with it: the hook was not asked, nothing outside moved, and a press
  /// that would have closed the route had there been no node simply vanished.
  ///
  /// The answer arrives a microtask later, since [NavigatorState.maybePop] is
  /// asynchronous by construction, and what it sets off is the same work
  /// [_NavigationNodeState._decideOutside] does at press time -- including its
  /// refusal to act on a decision that no longer applies.
  void _askInside(NodeNavigatorState navigator, Object? result) {
    unawaited(
      navigator._popInside(result).then((tookIt) {
        if (!tookIt && mounted) {
          widget.node._decideOutside(this, result);
        }
      }).onError<Object>((error, stackTrace) {
        _reportBackFailure(
          error,
          stackTrace,
          'while offering a system back to the navigator inside a '
          'NavigationNode',
        );
      }),
    );
  }

  /// Whether the node still stands where it stood when a press arrived.
  ///
  /// Asked of a decision that took time: the route may have been closed by
  /// something else or buried under a newer one, and the node may have been
  /// switched off, which gives up its place on that route as surely as leaving
  /// the tree does. [_route] is `null` for both of those last two, and identity
  /// is what tells a node that has moved from one that has not.
  bool _stillOn(ModalRoute<dynamic>? route) =>
      route != null && identical(_route, route) && route.isCurrent;

  bool _watchInnerStack(NavigationNotification notification) {
    if (notification.canHandlePop != _innerCanPop) {
      _innerCanPop = notification.canHandlePop;
      canPopNotifier.notifyOfChange();
    }

    // Heard, and -- while the node is switched off -- kept here. A node that
    // has given up its place on the route has nothing to say about a press,
    // and what its own subtree announces is nobody else's news: let it past,
    // and `WidgetsApp` tells the platform that the framework handles back, for
    // a stack this node has promised not to touch and which is usually not on
    // screen at all. The route goes on announcing what it holds for itself,
    // and it announces it without this node -- which is the whole of what
    // being switched off means.
    //
    // Kept rather than ignored: the value is what the node answers with the
    // moment it is switched back on, and nothing dispatches it again then.
    return !widget.node.widget.enabled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPopEntry();
  }

  @override
  void didUpdateWidget(_NodeBackDispatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `enabled` lives on the node's widget rather than on this one, so there
    // is nothing here to compare it against -- what is compared is the route
    // this is registered on, which is `null` while the node is disabled.
    _syncPopEntry();
  }

  /// Takes a place on the route, or gives it up, following
  /// [NavigationNode.enabled].
  void _syncPopEntry() {
    final nextRoute =
        widget.node.widget.enabled ? ModalRoute.of(context) : null;
    if (identical(nextRoute, _route)) {
      return;
    }

    _route?.unregisterPopEntry(this);
    _route = nextRoute;
    _route?.registerPopEntry(this);
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(this);
    _route = null;
    canPopNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<NavigationNotification>(
        onNotification: _watchInnerStack,
        child: widget.child,
      );
}

/// The answer a [_NodeBackDispatcher] gives, worked out when it is asked.
///
/// A [ValueNotifier] would hold an answer instead, and the node has no moment
/// at which to write one: what the answer depends on changes without telling
/// anybody. Listeners are still notified of what the node does hear about, so
/// that the framework's own idea of who handles the back gesture keeps up.
final class _NodeCanPopOutside extends ChangeNotifier
    implements ValueListenable<bool> {
  final _NodeBackDispatcherState _dispatcher;

  _NodeCanPopOutside(this._dispatcher);

  @override
  bool get value => _dispatcher._canPopOutside;

  void notifyOfChange() => notifyListeners();
}

/// The one observer a node hands its own navigator.
///
/// A `NavigatorObserver` can be given to one navigator and no more —
/// `NavigatorObserver.navigator` is read out of a static `Expando` the
/// framework writes when a navigator is built, under an assertion that nothing
/// was written there before. The observers of an application are bound to the
/// navigator of the application already, so handing those same instances to a
/// node is not a thing that can be done. This one belongs to the node; what it
/// retells to is bound to nothing at all, which is what lets a single
/// `RouteObserver` serve the application and every node in it at once.
final class _NodeObserver extends NavigatorObserver {
  final _NavigationNodeState _node;

  _NodeObserver(this._node);

  /// Whether [route] is the page the node builds for itself.
  ///
  /// That page stands for the route the node stands on, and the navigator
  /// above announced that one already — saying it again would give an
  /// application two screens where it has one, the second of them nameless.
  /// What is kept quiet about is the page itself, never an event that merely
  /// mentions it: a route pushed over it is announced with the page as its
  /// previous route, and that is what tells a `RouteAware` on the node's first
  /// page that something has covered it.
  bool _isOwnPage(Route<dynamic> route) =>
      identical(route.settings, _node._pages.single);

  /// Retells one event, to the observers the node was given and then to the
  /// ones it inherits.
  ///
  /// The navigator above is asked for here rather than remembered, the same way
  /// the route table it lends is read on every build: what an application hands
  /// its navigator is a list of its own, and a node that has been moved answers
  /// about where it is standing now.
  ///
  /// Both lists are walked through a copy, because neither belongs to the node.
  /// A delegate that takes itself off the list the moment it hears something is
  /// an ordinary shape, and walking the list itself threw a
  /// `ConcurrentModificationError` out of the middle of the navigator's flush —
  /// which left that navigator's debug lock raised and every later push of this
  /// node failing on an assertion, for the lifetime of the widget. Under a
  /// `MaterialApp` the framework walks a copy without meaning to, since
  /// `_effectiveObservers` is `widget.observers` with the hero controller added
  /// to it, so the same delegate survives on the navigator of the application:
  /// the difference would have been ours alone.
  ///
  /// A delegate that raises is reported and stepped over, which is a departure
  /// from the framework — a `Navigator` lets an observer's failure out, and it
  /// costs that navigator the rest of its flush and leaves its debug lock
  /// raised. The node cannot afford that here, because the observer that
  /// raises need not be anything to do with the node: an observer the
  /// application declared for its own navigator would otherwise take the
  /// navigator of every node it is retold to down with it, and take it down for
  /// good. The rest of the audience is told, and the failure arrives with this
  /// package named on it rather than disappearing.
  void _tell(void Function(NavigatorObserver observer) event) {
    _retell(_node.widget.observers, event);

    if (!_node.widget.observedFromAbove) {
      return;
    }

    final above = Navigator.maybeOf(_node.context);
    if (above != null) {
      _retell(above.widget.observers, event);
    }
  }

  /// Tells one list, without letting any of them stop the others.
  void _retell(
    List<NavigatorObserver> observers,
    void Function(NavigatorObserver observer) event,
  ) {
    for (final observer in List.of(observers)) {
      try {
        event(observer);
      } on Object catch (error, stackTrace) {
        _reportBackFailure(error, stackTrace, '$_retelling $observer');
      }
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Mounting, and the only push of the node's own page there ever is: the
    // page goes onto an empty navigator and never again, because a node does
    // not empty itself. `previousRoute` is what says so, and it has to be
    // asked rather than assumed: a `Page` is a `RouteSettings`, so a route
    // pushed with the settings of the route it stands on -- which inside a node
    // is the node's own page -- carries that very object, and the settings
    // alone cannot tell the two apart.
    if (previousRoute == null && _isOwnPage(route)) {
      return;
    }

    _tell((observer) => observer.didPush(route, previousRoute));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _tell((observer) => observer.didPop(route, previousRoute));

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _tell((observer) => observer.didRemove(route, previousRoute));

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _tell(
        (observer) => observer.didReplace(
          newRoute: newRoute,
          oldRoute: oldRoute,
        ),
      );

  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) {
    // Mounting again — the node's page becoming the top one when there was no
    // top before it. Becoming the top one later, once everything above it has
    // gone, is a change of what is on screen like any other, and an
    // application keeping track of where it is has to hear about that one.
    if (previousTopRoute == null && _isOwnPage(topRoute)) {
      return;
    }

    _tell((observer) => observer.didChangeTop(topRoute, previousTopRoute));
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) =>
      _tell((observer) => observer.didStartUserGesture(route, previousRoute));

  @override
  void didStopUserGesture() =>
      _tell((observer) => observer.didStopUserGesture());
}

/// The single page a node starts with.
///
/// It answers [ModalRoute.impliesAppBarDismissal] for itself, so that an
/// `AppBar` on the node's first page draws a back arrow even though the page is
/// the first of its navigator: pressing it leaves the node, which is somewhere
/// to go. The node used to say the same thing with a [LocalHistoryEntry] on the
/// route, and that cost it the ability to tell its own marker from a `Drawer`'s
/// — both are entries in the same list, and a route reports only whether that
/// list is empty.
final class _NodePage extends MaterialPage<void> {
  /// Whether a pop of this page goes on to the navigator above.
  final bool leavesTheNode;

  const _NodePage({
    required super.child,
    required this.leavesTheNode,
    super.restorationId,
  });

  @override
  Route<void> createRoute(BuildContext context) => _NodePageRoute(this);
}

final class _NodePageRoute extends PageRoute<void>
    with MaterialRouteTransitionMixin<void> {
  _NodePageRoute(_NodePage page) : super(settings: page);

  _NodePage get _page => settings as _NodePage;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  bool get impliesAppBarDismissal =>
      _page.leavesTheNode || super.impliesAppBarDismissal;
}

final class _NodeNavigator extends Navigator {
  final _NavigationNodeState node;

  const _NodeNavigator({
    super.key,
    required this.node,
    super.pages,
    super.observers,
    super.restorationScopeId,
    super.onDidRemovePage,
    super.onGenerateRoute,
    super.onUnknownRoute,
  });

  @override
  NavigatorState createState() => NodeNavigatorState._();
}

/// The state of the nested navigator a [NavigationNode] builds.
///
/// This is the type a `navigatorKey` is made of —
/// `GlobalKey<NodeNavigatorState>()` — and what that key resolves to, so a
/// caller outside the node can push, pop and read the stack of the navigator
/// inside it. Everything a [NavigatorState] offers is available here; what the
/// node changes is how a pop that the nested navigator cannot handle is
/// answered.
final class NodeNavigatorState extends NavigatorState {
  /// Made by the node, never by hand.
  ///
  /// The type is public because a `navigatorKey` is written with it and resolves
  /// to it, and everything else about it is a [NavigatorState]. What it needs is
  /// the widget a [NavigationNode] builds: that is where it reads the node from,
  /// and installed under any other `Navigator` it would fail on the first pop
  /// instead of at the line where the mistake was made. Nothing outside this
  /// library can put it there.
  NodeNavigatorState._();

  _NavigationNodeState get _node => (widget as _NodeNavigator).node;

  /// Asks this navigator and nothing else.
  ///
  /// [maybePop] leaves the node when the node has nothing of its own to close,
  /// which is what a caller wants and what the back arrow of an `AppBar` on the
  /// first page does. The node itself needs the other half of that answer — did
  /// anything below take the press — before it decides what happens outside.
  // ignore: discarded_futures
  Future<bool> _popInside(Object? result) => super.maybePop(result);

  /// Pops until the predicate matches, or until the node's own page.
  ///
  /// Unlike [NavigatorState.popUntil], the walk always ends on the page the
  /// node starts with: a node never empties itself, so a predicate matching
  /// nothing inside it stops there rather than leaving the node.
  @override
  void popUntil(RoutePredicate predicate) {
    // The walk ends on the node's own page, whatever the predicate says.
    // [NavigatorState.popUntil] pops and then looks at what is left on top,
    // over and over until the predicate matches what it finds there -- and a
    // pop that reaches this page takes nothing, since a node never empties
    // itself. A predicate matching nothing inside the node therefore left that
    // loop looking at the same route for ever, in the frame it was called
    // from.
    //
    // Stopping is the whole of the answer. Handing the pop over the way [pop]
    // does would take a route above for a walk that was never about the
    // outside, and it would do it once for every turn of the loop.
    super.popUntil((route) => route is _NodePageRoute || predicate(route));
  }

  /// Pops the top route of this navigator, or leaves the node.
  ///
  /// Unlike [NavigatorState.pop], this never takes the page the node starts
  /// with — a node does not empty itself. When there is nothing else left, an
  /// ordinary node hands the pop to the navigator above it, as often as it is
  /// asked, and a [NavigationNode.isRoot] one keeps it and does nothing.
  @override
  void pop<T extends Object?>([T? result]) {
    if (canPop()) {
      super.pop(result);

      return;
    }

    // Nothing of the node's own is left to close, and letting the base
    // implementation take the first page would leave the node with an empty
    // stack — a hole where the screen used to be. A root node keeps the pop
    // instead; any other node hands it to the navigator above, every time and
    // not merely the first.
    if (_node.widget.isRoot) {
      return;
    }

    final previous = this.previous;
    if (previous == null) {
      return;
    }

    // Held, rather than dropped with an `ignore`. Asking the navigator above
    // runs the guards of its route and then the route itself, both of them
    // user code, and a raise there would surface as an unhandled zone error
    // far from the press that caused it.
    unawaited(
      previous.maybePop(result).onError<Object>((error, stackTrace) {
        _reportBackFailure(
          error,
          stackTrace,
          'while handing a pop to the navigator above a NavigationNode',
        );

        return false;
      }),
    );
  }

  /// Asks this navigator to pop, and asks the one above when it will not.
  ///
  /// Unlike [NavigatorState.maybePop], an answer of `false` from the node's own
  /// stack is not the end: the way out of a node is the navigator above, and
  /// that one is asked next — which is the path the back arrow of an `AppBar`
  /// on the node's first page takes. A [NavigationNode.isRoot] node stops
  /// there and answers `false`.
  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    if (await super.maybePop(result)) {
      return true;
    }

    // The base implementation has just said that the first page of the node has
    // nothing to give up and nobody below refuses — which for an ordinary
    // navigator is where a pop stops. For a node it is where it leaves: the way
    // out is the navigator above, and this is the path the back arrow of an
    // `AppBar` takes.
    if (_node.widget.isRoot) {
      return false;
    }

    final previous = this.previous;

    return previous != null && await previous.maybePop(result);
  }
}

/// Access to the navigator above a given one.
extension PreviousNavigatorExtension on NavigatorState {
  /// The navigator above this one, if any.
  ///
  /// This is how a [NavigationNode] forwards a pop it cannot handle itself.
  NavigatorState? get previous {
    // [State.mounted] before [State.context], and not the `mounted` of the
    // context: `State.context` asserts on a state whose element is gone, so
    // asking the context whether it is mounted reads it first and throws --
    // the guard could only ever have held in a release build. A caller that
    // kept a [NavigatorState] past the life of its tree gets `null` here, the
    // way a getter answers rather than raising out of an ancestor walk.
    if (!mounted) {
      return null;
    }

    NavigatorState? prevNavigator;
    context.visitAncestorElements((element) {
      prevNavigator = Navigator.maybeOf(element);

      return false;
    });

    return prevNavigator;
  }
}

/// The name the node's own page is entered under, inside the node's own bucket.
const _nodePageRestorationId = 'node';

/// What the node was doing when it could not re-throw.
const _decidingBack = 'while deciding what a system back does in a '
    'NavigationNode';

/// What the node was doing when it could not re-throw.
///
/// Ends with the delegate itself: a failure that names the observer it came
/// from is one step of the diagnosis already done, and an application hands a
/// node several of them.
const _retelling = 'while retelling the navigation inside a NavigationNode to';

/// Reports what a node cannot re-throw.
///
/// A press is answered in more than one place, and most of those answer into a
/// future nobody holds or into a loop the framework runs over the entries of a
/// route. A failure there would surface as an unhandled zone error far from the
/// widget that caused it, or take the rest of that loop with it. Reported
/// instead, it arrives with this package named on it; the press is simply not
/// acted on, and the next one is asked as usual.
void _reportBackFailure(Object error, StackTrace? stack, String whileDoing) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'navigation_node',
      context: ErrorDescription(whileDoing),
    ),
  );
}
