// `unreachable_from_main` counts a library with a `vm:entry-point` in it as one
// with an entry point of its own, and then finds everything else in the file
// unreachable from it. What is here is reached from `main.dart` like any other
// lesson; the annotation below is a requirement of the framework, not a second
// way in.
// ignore_for_file: unreachable_from_main

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
///
/// The annotation is not decoration: the navigator asks for this function *by
/// name* when it builds the route again, and the name has to survive the
/// compiler for that. Without it the application starts, pushes, and falls over
/// on the way back -- «To closurize … from native code, it must be annotated».
@pragma('vm:entry-point')
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
        'engine makes after a true restart — and the dying of the tree below: '
        'the node, its navigator and every route on it really do go, and what '
        'comes back is built again from the bytes. What is pretended is only '
        'that the process died, and everything outside this lesson with it.',
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

  /// Starts with [kept] — nothing on a first launch, and what the system held
  /// on to when the application is coming back from being killed.
  ///
  /// This is the call the engine makes on a real device, with the bytes the
  /// platform kept, and it is the whole of the road back.
  void begin({Uint8List? kept}) =>
      handleRestorationUpdateFromEngine(enabled: true, data: kept);
}

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  final _manager = PocketRestorationManager();

  /// Counts the lives of the node: a new one is a new tree, from the navigator
  /// down, which is what makes the pretence worth anything.
  var _life = 0;

  RestorationBucket? _bucket;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_takeTheNewBucket);

    // Started after this build rather than inside it. Once the manager has
    // been started its bucket arrives *synchronously* -- `rootBucket` is a
    // `SynchronousFuture` from then on -- so starting it here would call
    // `setState` while this widget is still being mounted. The framework
    // allows that and it costs nothing: the element is dirty already, and
    // `markNeedsBuild` returns before it does anything. What it costs is the
    // reading -- the bucket would arrive by two roads instead of one, and the
    // quiet one would be the one that runs first.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _manager.begin();
      }
    });
  }

  void _takeTheNewBucket() {
    unawaited(
      _manager.rootBucket.then((bucket) {
        if (!mounted || identical(bucket, _bucket)) {
          return;
        }

        // A guard rather than a cure. Nothing in this lesson reaches here
        // from inside a build: the manager is started from the callback above
        // and from the button, and neither of those is one. But a listener is
        // not a thing whose callers stay listed, and `setState` in the
        // persistent-callbacks phase is an error the framework reports and
        // then trips over, one frame after another.
        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _bucket = bucket);
            }
          });

          return;
        }

        setState(() => _bucket = bucket);
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

    // What the system would have held on to, taken while the application is
    // still alive -- which is when it is taken on a device as well.
    final kept = _manager.saved;
    journal.log('kept ${kept?.length ?? 0} bytes, as a kill would');

    setState(() {
      // Everything below goes: the node, its navigator, the routes on it. That
      // is the part a pretended kill has to get right. Unwinding the stack of a
      // living navigator instead is a different thing entirely -- pressing this
      // during a transition took the navigator apart underneath the route that
      // was still arriving, and the framework said so.
      _life++;
      _bucket = null;
    });

    // The same manager, handed the bytes again. Replacing it instead would
    // leave the old one holding a serialisation the framework had already
    // scheduled for the next frame -- and that callback, arriving at a bucket
    // that no longer exists, takes the whole frame down with it. Replacing the
    // *data* is what a device does anyway, and the framework does the swap
    // itself: it hands out the new bucket first and disposes the old one after.
    _manager.begin(kept: kept);
    journal.logNode('started again with the bytes, the way a device does');
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
                    key: ValueKey(_life),
                    bucket: bucket,
                    child: const NavigationNode(
                      restorationScopeId: 'lesson',
                      child: _NodeHome(),
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
