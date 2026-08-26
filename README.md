# navigation_node

[![pub version](https://img.shields.io/pub/v/navigation_node)](https://pub.dev/packages/navigation_node)
[![license](https://img.shields.io/github/license/vi-k/navigation_node)](https://github.com/vi-k/navigation_node/blob/main/LICENSE)

A nested `Navigator` for Flutter. It puts a navigator in the middle of the
tree, and a dialog, a bottom sheet or a screen pushed through it is built
**below** that point rather than above the whole application — so everything
the screen put over its own subtree is still among the route's ancestors. The
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
state:

```
MaterialApp
└─ Navigator
   ├─ Screen
   │  └─ TicketScope
   │     └─ ScreenBody
   └─ Dialog             ← pushed here: TicketScope is not an ancestor
```

Put a node on the screen, push through it, and the route lands inside:

```
MaterialApp
└─ Navigator
   └─ Screen
      └─ TicketScope
         └─ NavigationNode
            ├─ ScreenBody
            └─ Dialog    ← pushed here: TicketScope is an ancestor
```

The other half is the system back button. A route asks its `PopEntry`s before
it closes, and a node is one: back closes what the node has open before it
touches the route around it, and a node per tab or per screen keeps that local.

## Using it

The node goes below whatever the screen puts over its content, and above the
content itself:

```dart
TicketScope(
  ticket: ticket,
  child: const NavigationNode(child: ScreenBody()),
)
```

From anywhere inside `ScreenBody`, push and open as usual:

```dart
// The dialog is built below the screen, so it reads what the screen put there.
showDialog<void>(
  context: context,
  useRootNavigator: false,
  builder: (context) => TicketDetails(TicketScope.of(context).ticket),
);

// A pushed route lands inside the node as well, ancestors and all.
Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (context) => const Details()),
);
```

**`useRootNavigator: false` is the one thing to remember.** `showDialog`,
`showModalBottomSheet` and their neighbours go to the navigator of the
application by default, and a route built there is next to your screen rather
than under it — which is the very thing a node exists to avoid.

The [example](https://github.com/vi-k/navigation_node/tree/main/example) shows
all of this running, in nine lessons, with a journal that says what answered
each back press.

## The parameters

| | | |
|---|---|---|
| `child` | the subtree the nested navigator shows first | required |
| `onPop` | answers a pop the node's route is asked about | `null` |
| `isRoot` | keeps a pop it cannot handle instead of forwarding it | `false` |
| `enabled` | whether the node takes part in its route's system back | `true` |
| `navigatorKey` | reaches `NodeNavigatorState` from outside | `null` |
| `observedFromAbove` | inherits the observers of the navigator above | `true` |
| `observers` | observers for this node alone | `const []` |

Each of them is documented in full in the API reference; what follows is what
you need before reaching for it.

## The system back

System back first asks the node's nested navigator to close its top route — and
"route" includes what a `Drawer` or a `showBottomSheet` puts on the page
without pushing anything, so a node takes none of that away and stands aside
for a press that closes one. Only when that navigator has nothing left to pop
do `onPop` and `isRoot` decide what happens outside the node.

`onPop` returns `true` to let the pop through, `false` to keep the route, or a
`Future<bool>` to decide after asking something — a confirmation dialog,
typically. The context it is given is one from inside the node, so
`showDialog(useRootNavigator: false)` puts that dialog in the node, below
everything the node stands under. An asynchronous hook is asked about one press
at a time, and an answer that arrives after the route has moved on takes
nothing. Anything that falls over on the way is reported through
`FlutterError.reportError`, and the press is simply not acted on.

`onPop` answers a pop the route is *asked* about: `Navigator.maybePop()`, the
back arrow of an `AppBar` above the node, the system back. A `Navigator.pop()`
of a route *inside* the node does not reach it — that takes the route rather
than asking it. So a button of your own that has to go through the hook wants
`maybePop`; one that must leave without being asked wants
`Navigator.of(context).previous?.pop()`, where `previous` is
`PreviousNavigatorExtension` on any navigator.

A node never empties itself. `Navigator.pop()` on its first page — from the
back arrow of an `AppBar`, say — leaves the node instead of taking that page
away: an ordinary node hands the pop to the navigator above it, as often as it
is asked, and a root node keeps it and does nothing. That arrow is drawn on
purpose: the page is the first route of its own navigator, so nothing about
that navigator implies a way back, and a root node draws no arrow there at all.

Nor does a node empty the navigator above, or overrule it. Handing a pop over
is asking, not taking: a `PopScope` the application put around the node is
answered by the application, not walked past, and a node on the first route of
the application has nothing to hand a pop to. `isRoot` is still worth setting
there: it says so at the node rather than leaving it to be discovered from the
stack. On a root node the hook is asked as it is anywhere else, and an answer
of `true` still takes nothing — such a hook is there for the press itself, a
"press again to exit", or a `SystemNavigator.pop()` the application makes on
its own terms.

## Named routes

Named routes work inside a node, and they land inside it. The nested navigator
borrows the route table of the navigator above — `MaterialApp.routes`, or its
`onGenerateRoute` — so `Navigator.of(context).pushNamed('/details')` from
inside a node builds `/details` below the node, with everything the screen put
over its subtree still among its ancestors. Nested nodes chain: each borrows
from the one above it.

## Observers

Observers of the application see the navigation inside a node. The navigator a
node builds reports to `MaterialApp.navigatorObservers` — a `RouteObserver`, an
analytics observer, a logger of your own — the way the navigator of the
application does, so a node costs nothing to put on a screen that is already
watched. What reaches them is a retelling: an observer instance belongs to one
navigator and one only, so the instances an application has already declared
cannot be handed to a node as well, and the node's own observer repeats to them
instead.

The price is that `NavigatorObserver.navigator` never names the node —
retelling binds nothing. An observer that reads it is asking about somewhere
else; `HeroController` is the framework's own, and has no business in
`observers:`. A delegate that raises is reported through
`FlutterError.reportError` and stepped over, so one failing observer takes
neither the rest of the audience nor the navigator of the node with it.

`observedFromAbove: false` keeps a node's navigation to itself, and
`observers:` names observers for one node. Do not name one that already stands
above: it would be told twice, and an assertion says so, wherever up the chain
the other mention is. Nodes chain, each inheriting the whole audience of the
navigator above it — so an outer node that is not observed cuts the nodes
inside it off from the application, though not from its own `observers:`. The
chain is made of nodes and nothing else: a plain nested `Navigator` of your own
standing between a node and the application has no proxy to pass anything on
with, and its own `observers` are all a node below it can find.

The page a node builds for itself is announced to nobody when the node mounts —
the navigator above has announced the route it stands for already. Everything
after that is passed on as it is, so a `RouteAware` on the node's first page is
told when a route pushed inside covers it, through a `RouteObserver<PageRoute>`
or wider: the node builds a `PageRoute`, not a `MaterialPageRoute`. What it is
never told is that the *application* covered it, and a node leaving the tree
says nothing about the routes it takes with it.

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
stack of one navigator, and a node never empties itself, so a predicate
matching nothing inside the node ends there rather than leaving.

## One node per tab: `NavigationNode(enabled:)`

A node takes part in the system back of the route it stands on. That is the
whole point of it, and it is fine as long as one node stands on a route.

Tabs break that assumption. The usual shape keeps a node per tab in an
`IndexedStack`, which builds every branch and shows one, so all of them are on
the route at once. A route asks each of its `PopEntry`s and calls each of them
back, so **one back press unwinds the stack of every tab**, the hidden ones
included: you press back on tab B and tab A quietly loses a screen.

Which tab is the one on screen is not something a node can work out — a hidden
branch of an `IndexedStack` reads exactly as a shown one. The application
knows, and `enabled` is where it says so:

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

Nodes inside nodes never need this: an inner node registers on the page of the
navigator above it rather than on the route both stand on.

## Where it comes from

This package was part of [scopo](https://pub.dev/packages/scopo) until 0.11.0,
and the two are made for each other: a scope over a screen is exactly the thing
a pushed route loses, and a node is what keeps it. Neither depends on the other
— this package imports nothing but Flutter — so a node is worth having whatever
puts state over your screens.
