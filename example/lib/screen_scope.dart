import 'package:flutter/material.dart';

/// Something a screen owns and its child windows are expected to reach.
///
/// A real one would be a controller, a repository or a form's state. A ticket
/// number is enough to answer the only question that matters here: did this
/// route end up under the screen, or above it?
class Ticket {
  /// What the screen would rather not lose track of.
  final String number;

  /// Creates a ticket.
  const Ticket(this.number);
}

/// Puts a [Ticket] over the subtree, the way a screen puts its state over its
/// own content.
///
/// A plain [InheritedWidget], and deliberately nothing more: the lessons are
/// about *where* a route is built, and every container answers that the same
/// way — it is found from below it and not from above. A real application
/// would put its state management here instead.
class ScreenScope extends InheritedWidget {
  /// What the screen owns and its child windows are expected to reach.
  final Ticket ticket;

  /// Creates the scope.
  const ScreenScope({
    required this.ticket,
    required super.child,
    super.key,
  });

  /// The ticket of the nearest [ScreenScope] above [context], if there is one.
  ///
  /// Reads without subscribing: the ticket never changes, and a dependency
  /// would only add a rebuild to reason about.
  static Ticket? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ScreenScope>()?.ticket;

  @override
  bool updateShouldNotify(ScreenScope oldWidget) =>
      ticket.number != oldWidget.ticket.number;
}

/// Says whether the scope of the screen is reachable from here.
///
/// This is the whole reason `NavigationNode` exists. A route pushed on the
/// application's navigator is built *above* the screen, so the screen's scope
/// is not among its ancestors and this reads "out of reach". A route pushed
/// inside a node is built below it, and the same lookup finds the ticket.
class ScopeReadout extends StatelessWidget {
  /// Creates the readout.
  const ScopeReadout({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ticket = ScreenScope.maybeOf(context);
    final found = ticket != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            found ? Icons.link : Icons.link_off,
            size: 18,
            color: found ? theme.colorScheme.tertiary : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              found
                  ? "ticket ${ticket.number} — the screen's scope is right here"
                  : "no ticket — the screen's scope is out of reach",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: found ? null : theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
