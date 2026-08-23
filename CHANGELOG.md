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
