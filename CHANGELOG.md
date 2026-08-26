## 0.3.0

* The stack inside a node can be restored. `NavigationNode(restorationScopeId:)`
  gives the node's navigator a name to keep it under, and what was pushed with
  `restorablePush` — or `restorablePushNamed`, through the route table the node
  borrows — comes back after the application is killed and started again. An
  ordinary `push` carries a closure and is never restored, which is the
  framework's rule rather than the node's; two nodes on one route need two
  names, and the framework says so itself rather than mixing one stack into the
  other. Nothing happens at all unless the application enables restoration for
  itself. This was the last of the three things `README.md` used to list under
  "what a node does not do" that was the node's own doing.
* `NodeNavigatorState.pop`, `maybePop` and `popUntil` are documented. They were
  overridden without a doc comment, so the API reference and the tooltip of an
  IDE showed what `NavigatorState` says about them — which for a node is untrue:
  its `popUntil` stops on the node's own page, and `pop` on that page leaves the
  node instead of taking it.
* The example gained four lessons, for the four things it did not show: one
  node per tab and what `enabled` is for, a name pushed inside a node, and the
  observers of an application hearing what a node does. Nine lessons now, and
  the tab one is the lesson to read first — it is the only shape where a node
  changes an application's behaviour without being asked to. The tenth shows
  restoration on a desktop, where the platform provides none: it keeps the
  blob itself and hands it back the way the engine would.
* `README.md` is rearranged around the reader rather than the widget. It opens
  with what a node is for, shows the tree with and without one, and then shows
  the code that uses it — including `useRootNavigator: false`, which used to be
  a clause in the middle of a paragraph about something else. The parameters are
  listed in one table, and what used to be a single 140-line section is now four
  named ones. What it stopped repeating is the part the API reference already
  said better.

## 0.2.0

* Observers reach the navigation inside a node.
  `NavigationNode(observedFromAbove:)` is `true` by default, so a
  `RouteObserver`, an analytics observer or a logger an application declared for
  its own navigator sees what a node pushes and pops the way it sees the rest of
  the application. **This changes what an application is told without a line of
  its own changing**: the silence of 0.1.x is `observedFromAbove: false`.
  `NavigationNode(observers:)` names observers for one node besides — one that
  is not on the navigator above, or one that should hear this node alone.
* Handing those instances over was never a thing that could be done — Flutter
  binds an observer to one navigator and asserts that it was bound to no other —
  so a node hands its navigator a single observer of its own and retells the
  seven hooks. Retelling binds nothing and unbinds nothing, which is what lets
  one instance serve the application and every node in it at once, and what
  makes `NavigatorObserver.navigator` say nothing about the node: it is `null`
  for an observer that is never anything but a delegate, it is the navigator of
  the application for one the application declared, and it is never the
  navigator whose navigation was just retold. An observer that reads it —
  `HeroController` is the framework's own — has no business here.
* Nodes chain, each inheriting the whole audience of the navigator above it. A
  node that is not observed cuts the nodes inside it off from the application,
  though not from its own `observers`, which are part of that audience too.
* The page a node builds for itself is announced to nobody when the node mounts:
  it stands for the route the node stands on, which the navigator above has
  announced already, and announcing it again would give an application two
  screens where it has one, the second of them nameless. Everything after that
  is passed on as it is — a route pushed over that page names it as its previous
  route, which is what tells a `RouteAware` on the node's first page that
  something has covered it.
* An observer that already stands above is refused by an assertion when it is
  named in `observers` as well — the nodes between are walked through, so a name
  repeated further up the chain is refused too — and so is one observer named
  twice in `observers` itself. Either would otherwise be told twice, and a
  `RouteObserver` would wake its subscribers twice for one push. A delegate that
  raises is reported through `FlutterError.reportError`, with the delegate
  named, and stepped over: the observer that falls over need not be anything to
  do with the node, and letting it out took the node's navigator down with it
  for good.
* The chain is made of nodes: a plain nested `Navigator` of an application's own
  standing between a node and the application passes nothing on, since only a
  node carries a proxy to pass it with.
* A node says nothing as it leaves the tree, and a `RouteAware` on its first
  page is told when the node covers it but not when the application does. Both
  are written down in `README.md`.

## 0.1.1

* Named routes work inside a node now, and land inside it. The nested navigator
  is handed one page and nothing else, so `pushNamed` from inside a node reached
  a navigator that had never heard of `routes:` and ended in an assertion of the
  framework — while the application had declared its routes in the one place
  there is to declare them. A node borrows the route table of the navigator
  above, so a name means the same thing inside a node as outside it, and
  `/details` pushed from inside is built below the node, with the screen's own
  scope among its ancestors. Nested nodes chain, each borrowing from the one
  above. Still not forwarded, and now written down in `README.md`: observers,
  and a restoration scope.
* Fix `popUntil` never finishing inside a node. `NavigatorState.popUntil` pops
  and then looks at what is left on top, over and over until its predicate
  matches — and a pop that reaches the node's own page takes nothing, since a
  node never empties itself. A predicate matching nothing inside the node
  therefore left that loop looking at the same route for ever, in the frame it
  was called from, with the application stopped. The walk now ends on the node's
  own page.
* Fix a back press vanishing when something below the node announced that it
  could handle a pop and then did not. A `Navigator` or `Router` of your own,
  deeper than the node's, is heard by the node exactly as the node's own
  navigator is, while the only navigator a node can hand a press to is its own —
  which had nothing to give up and said so into a future nobody read. The press
  reached neither `onPop` nor the route above and simply disappeared, where with
  no node there at all it would have closed the route. A press nothing below
  took is now the node's to answer, as it always should have been.
* Fix a disabled node still telling the framework that the back gesture is
  handled. What its own subtree announced went past it and reached
  `WidgetsApp`, which passes it to the platform — so a hidden tab of an
  `IndexedStack` suppressed the predictive back gesture for a stack nobody could
  see and the node had promised not to touch. A node with no place on the route
  now keeps that news to itself, and goes on hearing it for the moment it is
  switched back on.
* Fix an answer from an asynchronous `onPop` still taking the route after the
  node was switched off. Confirming a dialog after switching tabs took the route
  the node had already given up its place on. Such an answer now takes nothing,
  the way an answer arriving under a newer route does.
* Report a failure from a synchronous `onPop`, from the guard read on the way
  out of the node, and from the pop handed to the navigator above — the three
  places where the promise in `README.md` was wider than the code. A synchronous
  raise used to travel out through the loop a route runs over its entries,
  taking any `PopScope` of yours beside the node with it; a raise in the
  handover was left in a future nobody held. All of them are reported through
  `FlutterError.reportError` now, and the press is simply not acted on.
* Correct what the documentation says about `Navigator.pop()`. It never reaches
  `onPop` from a route *inside* the node, which is what was meant — but on the
  node's first page there is no such route to take, and the pop leaves the node
  by asking the navigator above, whose route the node is a `PopEntry` of. The
  hook is reached there, and now it says so. `README.md` also grew a section on
  what a node does not do: named routes, `Hero` animations and where `popUntil`
  stops.
* Fix an error reported from a node naming the wrong library. Anything that
  falls over while an asynchronous `onPop` is being answered — the question
  itself, a confirmation dialog, the guard on the route — is reported through
  `FlutterError.reportError`, and the report said it came from `scopo`. It says
  `navigation_node` now, wherever a report comes from.

## 0.1.0

* First release. `NavigationNode`, `NodeNavigatorState` and
  `PreviousNavigatorExtension` were part of [scopo](https://pub.dev/packages/scopo)
  up to and including its 0.10.0, and arrive here unchanged — same code, same
  suite of 43 tests, same six lessons in `example/`. A consumer of scopo 0.11.0
  or later adds this package and changes one import; there is nothing else to
  migrate.
* The reason for the move is that it never belonged in a package about scopes:
  it imports nothing but Flutter, nothing inside scopo used it, and somebody
  looking for a nested navigator had no way of finding it in a package
  described as dependency injection. It still pairs with scopo the way it
  always did.
