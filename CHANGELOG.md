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
