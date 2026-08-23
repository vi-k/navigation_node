import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Turns Flutter's leak tracker on for this example's suite.
///
/// The package's own suite runs with the tracker on
/// (`test/flutter_test_config.dart` beside it, and the reason is written
/// there). An example is where the package is used the way a reader would use
/// it, so a notifier left undisposed here says the same thing about the
/// package as one left undisposed in a unit test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  await testMain();
}
