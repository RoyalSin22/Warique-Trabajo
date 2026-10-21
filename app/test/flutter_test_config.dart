import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'support/container.dart';

/// Runs before every test file: an in-memory SharedPreferences for screens that save drafts.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  testPrefs = await SharedPreferences.getInstance();
  await testMain();
}
