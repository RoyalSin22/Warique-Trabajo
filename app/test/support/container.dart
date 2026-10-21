import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:warique_app/core/alerts.dart';
import 'package:warique_app/core/api_client.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/state/realtime.dart';
import 'package:warique_app/state/session.dart';

import 'fixtures.dart';

const testServer = 'http://server.test';

/// Set by test/flutter_test_config.dart; emptied for every test by [testPreferencesOverride].
late SharedPreferences testPrefs;

/// Device storage for one test, starting empty (no draft left over from a previous test).
Override testPreferencesOverride() {
  testPrefs.clear();
  return sharedPreferencesProvider.overrideWithValue(testPrefs);
}

Session testSession(Role role, {int userId = 1}) => Session(
  serverUrl: testServer,
  token: 'token',
  user: AppUser(id: userId, username: 'u', fullName: 'Usuario ${role.label}', role: role),
);

/// Records alerts instead of touching the audio and wakelock plugins.
class FakeAlerts implements Alerts {
  final played = <({AlertTone tone, bool vibrate})>[];
  final screenOn = <bool>[];
  bool gestureNeeded = false;

  @override
  bool get needsUserGesture => gestureNeeded;

  @override
  Future<void> play(AlertTone tone, {bool vibrate = false}) async =>
      played.add((tone: tone, vibrate: vibrate));

  @override
  Future<void> keepScreenOn(bool on) async => screenOn.add(on);

  @override
  void dispose() {}
}

/// Overrides for a logged-in session backed by a fake HTTP server and realtime feed.
List<Override> sessionOverrides({
  required Role role,
  required RecordingHttp http,
  required FakeRealtime realtime,
  FakeAlerts? alerts,
  int userId = 1,
}) => [
  currentSessionProvider.overrideWithValue(testSession(role, userId: userId)),
  testPreferencesOverride(),
  alertsProvider.overrideWithValue(alerts ?? FakeAlerts()),
  apiClientProvider.overrideWithValue(
    ApiClient(baseUrl: testServer, token: 'token', httpClient: http.client),
  ),
  realtimeClientProvider.overrideWithValue(realtime),
  realtimeConnectedProvider.overrideWith((ref) => Stream.value(true)),
];
