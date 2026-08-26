import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:navigation_node/navigation_node.dart';

import '../journal.dart';
import '../lesson.dart';

/// Builds the page the restorable push puts on the node.
///
/// A top-level function on purpose: a restorable push writes down a reference
/// to the builder rather than the closure at the call site, and that is the
/// whole reason it can be built again after the application is gone. An
/// ordinary `push` takes a closure, which cannot be written down at all.
Route<void> _restorableDetails(BuildContext context, Object? arguments) =>
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'restorable page'),
      builder: (context) => const SamplePage(title: 'Pushed restorably'),
    );

/// Lesson 10: what survives the application being killed, and what does not.
final restorationLesson = Lesson(
  title: '10. What survives a restart',
  summary: 'restorationScopeId brings the stack back — for restorable pushes',
  explanation: const [
    'Given a `restorationScopeId`, the navigator inside a node writes down its '
        'history, and the system hands that back when it starts the '
        'application again after killing it. The two pushes below are '
        'indistinguishable on screen; the difference is what is left of them '
        'afterwards.',
    'macOS never kills an application for you and keeps nothing, so this '
        'lesson keeps the data itself and hands it back on the button. What is '
        'real here is the data and the road it takes in — the same call the '
        'engine makes after a true restart. What is pretended is the dying: '
        'the widgets never went anywhere.',
  ],
  instruction: 'push one of the two pages, press "Kill and bring it back", and '
      'see which of them is there afterwards. On Android the real thing is '
      '"Don\'t keep activities" in the developer options.',
  stage: (context) => const _Stage(),
);

/// Keeps the restoration data in its pocket instead of handing it to a
/// platform.
///
/// **A prop for this lesson, not a recipe for an application.** State
/// restoration is the platform's work: on Android and iOS the system saves
/// this blob when it kills the application and gives it back when it starts it
/// again. macOS does neither, so there is nothing to see there — and this
/// class is what makes the road visible: it catches what the framework sends
/// out ([sendToEngine]) and hands it back in ([handleRestorationUpdateFromEngine]),
/// which is the very call the engine makes after a real restart.
class PocketRestorationManager extends RestorationManager {
  /// What was last written down, and what a kill would have kept.
  Uint8List? saved;

  @override
  void initChannels() {
    // Deliberately not connected to the engine: there is nothing on the other
    // end of that channel on a desktop, and this manager is its own platform.
  }

  @override
  Future<void> sendToEngine(Uint8List encodedData) async {
    saved = encodedData;
  }

  /// Starts with nothing kept, the way a first launch does.
  void begin() => handleRestorationUpdateFromEngine(enabled: true, data: null);

  /// Hands [data] back the way the engine does after a restart.
  void bringBack(Uint8List? data) =>
      handleRestorationUpdateFromEngine(enabled: true, data: data);
}

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  final _manager = PocketRestorationManager();
  final _navigatorKey = GlobalKey<NodeNavigatorState>();

  RestorationBucket? _bucket;

  @override
  void initState() {
    super.initState();
    _manager
      ..begin()
      ..addListener(_takeTheNewBucket);
    _takeTheNewBucket();
  }

  void _takeTheNewBucket() {
    unawaited(
      _manager.rootBucket.then((bucket) {
        if (mounted) {
          setState(() => _bucket = bucket);
        }
      }),
    );
  }

  @override
  void dispose() {
    _manager
      ..removeListener(_takeTheNewBucket)
      ..dispose();
    super.dispose();
  }

  void _killAndBringBack() {
    final journal = JournalScope.of(context, listen: false);

    // Taken before the stack is unwound, which is the order that reads
    // correctly rather than the order that is required: serialisation is
    // deferred to a post-frame callback, so reading it after the pops would in
    // fact give the same bytes -- until something makes a frame in between.
    final snapshot = _manager.saved;
    journal.log('kept ${snapshot?.length ?? 0} bytes, as a kill would');

    // Back to the node's own page, which is where a fresh start would leave
    // it. `popUntil` stops there by itself — a node never empties itself.
    _navigatorKey.currentState?.popUntil((route) => false);

    _manager.bringBack(snapshot);
    journal.logNode('handed the bytes back the way a restart does');
  }

  @override
  Widget build(BuildContext context) {
    final bucket = _bucket;

    return Stage(
      label: 'NavigationNode (restorationScopeId: "lesson")',
      isNode: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.tonalIcon(
              onPressed: _killAndBringBack,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Kill and bring it back'),
            ),
          ),
          Expanded(
            child: bucket == null
                ? const Center(child: CircularProgressIndicator())
                // The scope goes here, around the node itself: the one that
                // `MaterialApp.restorationScopeId` installs reads the manager
                // of the binding, and would never see this one.
                : UnmanagedRestorationScope(
                    bucket: bucket,
                    child: NavigationNode(
                      navigatorKey: _navigatorKey,
                      restorationScopeId: 'lesson',
                      child: const _NodeHome(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NodeHome extends StatelessWidget {
  const _NodeHome();

  @override
  Widget build(BuildContext context) => NodeHome(
        title: 'first page of the node',
        child: ScrollIfTight(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _RestorablePushButton(),
              const SizedBox(height: 8),
              PushButton(
                label: 'Push the ordinary way',
                pageName: 'ordinary page',
                builder: (context) =>
                    const SamplePage(title: 'Pushed the ordinary way'),
              ),
            ],
          ),
        ),
      );
}

class _RestorablePushButton extends StatelessWidget {
  const _RestorablePushButton();

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        onPressed: () {
          JournalScope.of(context, listen: false)
              .log('pushed "restorable page"');
          Navigator.of(context).restorablePush(_restorableDetails);
        },
        child: const Text('Push restorably'),
      );
}
