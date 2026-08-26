# navigation_node

[![pub version](https://img.shields.io/pub/v/navigation_node)](https://pub.dev/packages/navigation_node)
[![license](https://img.shields.io/github/license/vi-k/navigation_node)](https://github.com/vi-k/navigation_node/blob/main/LICENSE)

A nested `Navigator` for Flutter. A dialog, a bottom sheet or a pushed screen
opened through it is built **below** the screen that opened it rather than above
it, so everything that screen puts over its subtree is still reachable from
those routes — which is not true of the root navigator of an application. The
system back reaches the innermost node first.

```dart
NavigationNode(child: const ScreenBody())
```

One widget, no configuration, nothing to set up at the top of the application.

## What it is for

A screen usually puts something over its own content: a controller, a form's
state, a repository, an `InheritedWidget`, whatever a state-management package
of your choice provides. A route pushed on the application's navigator is built
next to that screen and not under it, so none of it is among the route's
ancestors — the dialog you opened from the screen cannot read the screen's own
state. Put a node on the screen, push through it, and the route lands inside.

The other half is the system back button. A route asks its `PopEntry`s before it
closes, and a node is one: back closes what the node has open before it touches
the route around it, and a node per tab or per screen keeps that local.

## The node

`navigatorKey` exposes the inner `NodeNavigatorState` when a caller needs to
push from outside. It is fixed for the lifetime of the node — it is the key the
nested navigator is built with, so another one would mean another navigator and
an empty stack — and handing over a different one is refused by an assertion.
Hold it in a `State` field rather than writing `GlobalKey()` inside `build`.

`observedFromAbove` and `observers` say who hears the navigation inside the
node; both are described further down. `isRoot` marks a node that must not
forward a pop any further. `onPop` intercepts the system back gesture: return
`true` to let the pop through, `false` to keep the route, or a `Future<bool>`
to decide after asking something — a confirmation dialog, typically. The context
it is given is one from inside the node, so `showDialog(useRootNavigator: false)`
puts that dialog in the node, below everything the node stands under.

An asynchronous `onPop` is asked once at a time: a back press arriving while an
answer is still pending is dropped rather than starting a second question. And
an answer is only acted on if it still applies — if the route the node sits on
was closed by something else, or buried under a newer one, a `true` takes
nothing, since a pop would otherwise take whatever is on top instead of what
was asked about.

Anything that falls over on the way — the question itself, or a guard the
application put on the route, which is read when the node asks what a pop there
would do — is reported through `FlutterError.reportError` rather than left in a
chain nobody holds, where it would surface as an unhandled zone error far from
the widget that caused it. The press is simply not acted on, and the next one is
asked as usual.

System back first asks the node's nested navigator to close its top route —
and "route" includes what a `Drawer` or a `showBottomSheet` puts on the page
without pushing anything, so a node takes none of that away. Only when that
navigator has nothing left to pop do `onPop` and `isRoot` decide what
happens outside the node. The two never compete: on a root node the hook is
asked as it is anywhere else, and an answer of `true` still takes nothing, since
a root node has nothing outside it to let the pop through to. Such a hook is
there for the press itself — a "press again to exit", or a `SystemNavigator
.pop()` the application makes on its own terms.

A node never empties itself. `Navigator.pop()` on its first page — from the back
arrow of an `AppBar`, say — leaves the node instead of taking that page away: an
ordinary node hands the pop to the navigator above it, as often as it is asked,
and a root node keeps it and does nothing.

Nor does it empty the navigator above, or overrule it. Handing a pop over is
asking, not taking: a node placed on the first route of the application has
nothing outside it to hand a pop to and hands over nothing, and a `PopScope` the
application put around the node is answered by the application, not walked past.
`isRoot` is still worth setting on a node that is the first route: it says so at
the node rather than leaving it to be discovered from the stack.

An `AppBar` on the node's first page draws a back arrow, and pressing it leaves
the node. That is the node's doing: the page is the first route of its own
navigator, so nothing about that navigator implies a way back. A root node draws
no arrow there, since it keeps a pop to itself and there would be nowhere to go.

`onPop` answers a pop the route is *asked* about, which is more than the system
back and less than every pop. The node is a `PopEntry` of the route it stands
on, so `Navigator.maybePop()` and the back arrow of an `AppBar` above the node
reach the hook as much as a system back does. A `Navigator.pop()` of a route
*inside* the node does not: it takes that route rather than asking it, and no
`PopEntry` is consulted. On the node's first page there is no such route to
take — the pop leaves the node instead, and leaving is asking the navigator
above, whose route this node is a `PopEntry` of, so the hook is reached there as
well. A button of your own that has to go through the hook wants `maybePop`; one
that must leave without being asked about wants
`Navigator.of(context).previous?.pop()`.

A node stands aside for a press the route will handle by itself. A `Drawer` or a
`showBottomSheet` above the node puts a local history entry on the route the
node stands on, and a route asks its `PopEntry`s before it looks at that entry —
so a node that always said "do not pop" took a press whose whole job was to
close a drawer, and with an `onPop` that refused, the drawer could not be closed
with back at all. `ModalRoute.willHandlePopInternally` is what the node reads,
at press time, and it means "somebody else's entry": the node gave up keeping
one of its own precisely because a route reports only whether that list is
empty.

`PreviousNavigatorExtension.previous` gives the navigator above a given one,
which is how a node forwards a pop it cannot handle itself.

Named routes work inside a node, and they land inside it. The nested navigator
borrows the route table of the navigator above — `MaterialApp.routes`, or its
`onGenerateRoute` — so `Navigator.of(context).pushNamed('/details')` from inside
a node builds `/details` below the node, with everything the screen put over its
subtree still among its ancestors. Nested nodes chain: each borrows from the one
above it.

Observers of the application see the navigation inside a node. The navigator a
node builds reports to `MaterialApp.navigatorObservers` — a `RouteObserver`, an
analytics observer, a logger of your own — the way the navigator of the
application does, so a node costs nothing to put on a screen that is already
watched. What a node hands its own navigator is a single observer of its own,
and it retells what it hears: Flutter binds an observer instance to one
navigator and asserts that it was bound to no other, so the instances an
application has already declared cannot be handed over as well.

Retelling binds nothing and unbinds nothing, and that is what lets one instance
serve the application and every node in it at once. The price is that
`NavigatorObserver.navigator` says nothing about the node. It is `null` for an
observer that is never anything but a delegate; it is the navigator of the
application for one the application declared; and it is never the navigator
whose navigation has just been retold. An observer that reads it is asking about
somewhere else — `HeroController` is the framework's own, and a node has nothing
to do with it anyway. A delegate that raises is reported through
`FlutterError.reportError` and stepped over, so that one failing observer takes
neither the rest of the audience nor the navigator of the node with it.

`observedFromAbove: false` keeps a node's navigation to itself, and `observers:`
names observers for one node — one that is not on the navigator above, or one
that should hear this node alone. Do not name one that already stands above: it
would be told twice, and an assertion says so, wherever up the chain the other
mention is. Nodes chain: a node inside a node inherits the whole audience of the
navigator above it, so an outer node that is not observed cuts the nodes inside
it off from the application — but not from its own `observers:`, which are part
of that audience as well.

The chain is made of nodes, and of nothing else. What a node inherits is the
list the nearest `Navigator` above it was handed, so a plain nested `Navigator`
of your own standing between a node and the application passes nothing on: it
has no proxy to pass anything with, and its own `observers` are all the node can
find. Name them on the node itself when that is the shape you have.

The page a node builds for itself is announced to nobody when the node mounts.
It stands for the route the node stands on, and the navigator above has
announced that one already — otherwise an application would see two screens
where it has one, and the second of them nameless. Everything after that is
passed on as it is. A route pushed over that page names it as its previous
route, which is what tells a `RouteAware` on the node's first page that
something has covered it — through a `RouteObserver<PageRoute>` or wider, since
the node builds a `PageRoute` and not a `MaterialPageRoute`. The page becoming
the topmost one again is announced too, nameless as it is.

Two things a node tells nobody. It says nothing as it leaves the tree: a node
taken off screen with a stack still inside it disposes those routes the way any
nested navigator does, without a `didPop` or a `didRemove` for any of them, so
an observer that counts what is open closes its own books when the route holding
the node goes. And a `RouteAware` on the node's first page hears that the node
covered it, never that the application did — the route it is subscribed to is
the node's page, and what the application pushes goes on another navigator
entirely.

## What a node does not do

**Nothing inside a node is restored.** The nested navigator is given no
`restorationScopeId`, so a stack pushed inside a node does not survive the
application being killed and brought back: it starts again from the node's own
page.

**A `Hero` does not fly between routes pushed inside a node.** That is Flutter's
own doing rather than the node's: a `Navigator` hides the `HeroControllerScope`
above it from its own subtree, so every nested navigator is left without a hero
controller until the application puts one there. Wrap the node in a
`HeroControllerScope` of your own if you want the animation.

**`popUntil` stops on the node's own page.** The walk it makes is about the
stack of one navigator, and a node never empties itself, so a predicate matching
nothing inside the node ends there rather than leaving.

## One node per tab: `NavigationNode(enabled:)`

A node takes part in the system back of the route it stands on. That is the
whole point of it — a back press closes what the node has open before it
touches the route around it — and it is fine as long as one node stands on a
route.

Tabs break that assumption. The usual shape keeps a node per tab in an
`IndexedStack`, which builds every branch and shows one, so all of them are on
the route at once. A route asks each of its `PopEntry`s and calls each of them
back, so **one back press unwound the stack of every tab**, the hidden ones
included: you pressed back on tab B and tab A quietly lost a screen.

The node cannot work out which of them is the one on screen. A hidden branch of
an `IndexedStack` — and an `Offstage` subtree — answers `TickerMode.of(context)`
and `ModalRoute.of(context)` exactly as a shown one does, and the order sibling
nodes register in says nothing about which is visible. The application knows,
and `enabled` is where it says so:

```dart
IndexedStack(
  index: _tab,
  children: [
    for (var i = 0; i < tabs.length; i++)
      NavigationNode(
        enabled: i == _tab,
        child: tabs[i],
      ),
  ],
)
```

A disabled node takes no place on the route: it is not asked and it is not
called back. Everything else goes on working — its nested navigator keeps its
stack, and `Navigator.of(context)` from inside still pushes and pops there, so
switching back to the tab finds it where it was left.

Nodes nested one inside another never need this: an inner node registers on the
page of the navigator above it rather than on the route both stand on, so two of
them are never asked about the same press.

The ambiguity is Flutter's own — two `PopScope`s on one route are both consulted
— and an application resolves it the same way.

## Example

[example](https://github.com/vi-k/navigation_node/tree/main/example)
— the node on its own, in six lessons: nested navigators, dialogs that belong to
the screen, `onPop`, `isRoot`, nodes inside nodes, and a system back you can
press on a desktop, with a journal showing what answered each press.

## Where it comes from

This package was part of [scopo](https://pub.dev/packages/scopo) until 0.11.0,
and the two are made for each other: a scope over a screen is exactly the thing
a pushed route loses, and a node is what keeps it. Neither depends on the other
— this package imports nothing but Flutter — so a node is worth having whatever
puts state over your screens.
