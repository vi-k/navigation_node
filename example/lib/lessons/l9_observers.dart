import 'dart:async';

import 'package:flutter/material.dart';
import 'package:navigation_node/navigation_node.dart';

import '../journal.dart';
import '../lesson.dart';

/// The name of the page this lesson pushes.
///
/// The application's observer reports this page and nothing else. A real one
/// reports everything, of course — this one is filtered so that the journal of
/// the other eight lessons stays about those lessons.
const observedPageName = 'observed page';

/// Writes what it hears to the journal, whichever navigator it hears it from.
///
/// This is the shape of every observer an application already has — a
/// `RouteObserver`, an analytics observer, a logger — and the point of the
/// lesson is that it takes nothing at all to make one see inside a node.
class JournalNavigatorObserver extends NavigatorObserver {
  final Journal _journal;
  final String _whose;

  /// Creates an observer that writes to [journal] under the name [whose].
  JournalNavigatorObserver(Journal journal, String whose)
      : _journal = journal,
        _whose = whose;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != observedPageName) {
      return;
    }

    _journal.logNode('$_whose heard: pushed "$observedPageName"');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != observedPageName) {
      return;
    }

    _journal.logNode('$_whose heard: popped "$observedPageName"');
  }
}

/// Lesson 9: the observers of the application see inside the node.
final observersLesson = Lesson(
  title: '9. Observers see inside',
  summary: 'What the application already watches with, watches the node too',
  explanation: const [
    'The navigator a node builds reports to the observers of the navigator '
        'above it — the ones the application declared in '
        '`MaterialApp.navigatorObservers`. Nothing has to be passed to the '
        'node for that: `observedFromAbove` is true to begin with.',
    '`observers:` names an observer for one node besides, and that one hears '
        'the node whatever the switch says. Turn the switch off and the '
        'application stops hearing; the observer given to the node does not.',
  ],
  instruction: 'push the page with the switch on, then off, and read which of '
      'the two lines the journal gets each time.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  /// The observer this node is given by hand, kept rather than rebuilt.
  ///
  /// It is bound to no navigator — that is what lets a node retell to it — but
  /// it is still one object per node, and a new one on every build would be a
  /// new audience on every build.
  late final JournalNavigatorObserver _ours = JournalNavigatorObserver(
    JournalScope.of(context, listen: false),
    'the observer given to the node',
  );

  bool _fromAbove = true;

  @override
  Widget build(BuildContext context) => Stage(
        label: 'NavigationNode',
        isNode: true,
        child: NavigationNode(
          observedFromAbove: _fromAbove,
          observers: [_ours],
          child: NodeHome(
            title: 'first page of the node',
            child: ScrollIfTight(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 340,
                    child: SwitchListTile(
                      value: _fromAbove,
                      onChanged: (value) => setState(() => _fromAbove = value),
                      title: const Text('observedFromAbove'),
                      subtitle: Text(
                        _fromAbove
                            ? 'the application hears this node'
                            : 'the application hears nothing from this node',
                      ),
                      dense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _ObservedPushButton(),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ObservedPushButton extends StatelessWidget {
  const _ObservedPushButton();

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        onPressed: () => unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: observedPageName),
              builder: (context) => const SamplePage(
                title: 'A page the observers hear about',
              ),
            ),
          ),
        ),
        child: const Text('Push a page inside the node'),
      );
}
