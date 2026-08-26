import 'dart:async';

import 'package:flutter/material.dart';
import 'package:navigation_node/navigation_node.dart';

import '../journal.dart';
import '../lesson.dart';
import '../screen_scope.dart';

/// The name the application declares in `MaterialApp.routes`.
///
/// One table, one name — and it means the same thing from inside a node as it
/// does from anywhere else, which is the whole of this lesson.
const detailsRouteName = '/details';

/// Lesson 8: a name pushed inside a node builds inside the node.
final namedRoutesLesson = Lesson(
  title: '8. Names work inside',
  summary: 'pushNamed inside a node builds the route inside it',
  explanation: const [
    'A node is handed one page and nothing else, so a name pushed inside it '
        'used to reach a navigator that had never heard of `routes:`. It now '
        "borrows the route table of the navigator above — the application's "
        'own — and builds the name below the node.',
    'So the same name means the same thing in both places, and where it lands '
        'is decided by the navigator you pushed it on: inside the node it '
        'keeps the screen above it, on the application it does not.',
  ],
  instruction: 'push the same name in both places and read the line about the '
      "screen's ticket. Then press System back and watch which one the node "
      'closes by itself.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) => const ScreenScope(
        ticket: Ticket('N-7'),
        child: Stage(
          label: 'NavigationNode',
          isNode: true,
          child: NavigationNode(
            child: NodeHome(
              title: 'first page of the node',
              child: ScrollIfTight(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NamedPushButton(
                      label: 'pushNamed inside the node',
                      onTheApplication: false,
                    ),
                    SizedBox(height: 8),
                    _NamedPushButton(
                      label: 'pushNamed on the application',
                      onTheApplication: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Pushes [detailsRouteName] on the node's navigator, or on the one above all.
class _NamedPushButton extends StatelessWidget {
  final String label;
  final bool onTheApplication;

  const _NamedPushButton({
    required this.label,
    required this.onTheApplication,
  });

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        onPressed: () {
          final where = onTheApplication ? 'the application' : 'the node';
          final journal = JournalScope.of(context, listen: false)
            ..log('pushed "$detailsRouteName" on $where');

          unawaited(
            Navigator.of(context, rootNavigator: onTheApplication)
                .pushNamed<void>(detailsRouteName)
                .then((_) => journal.log('"$detailsRouteName" was closed')),
          );
        },
        child: Text(label),
      );
}
