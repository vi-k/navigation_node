import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Turns Flutter's leak tracker on for every test under `test/`.
///
/// The tracker is off by default (`LeakTesting.enabled` starts as `false`),
/// and this file is the only place that can switch it on for the whole suite:
/// `flutter_test_config.dart` wraps `main()` of every test in the directory
/// tree below it.
///
/// A node owns a nested `Navigator`, a listener on its stack and an entry on
/// the route above it, and it has to give all three back when it leaves. The
/// tracker is what says so without a line of per-test bookkeeping:
/// `ChangeNotifier` is instrumented by the framework itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  await testMain();
}
