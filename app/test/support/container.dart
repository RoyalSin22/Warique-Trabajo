import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:warique_app/core/api_client.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/state/realtime.dart';
import 'package:warique_app/state/session.dart';

import 'fixtures.dart';

const testServer = 'http://server.test';

Session testSession(Role role) => Session(
      serverUrl: testServer,
      token: 'token',
      user: AppUser(id: 1, username: 'u', fullName: 'Usuario ${role.label}', role: role),
    );

/// Overrides for a logged-in session backed by a fake HTTP server and realtime feed.
List<Override> sessionOverrides({
  required Role role,
  required RecordingHttp http,
  required FakeRealtime realtime,
}) =>
    [
      currentSessionProvider.overrideWithValue(testSession(role)),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: testServer, token: 'token', httpClient: http.client),
      ),
      realtimeClientProvider.overrideWithValue(realtime),
      realtimeConnectedProvider.overrideWith((ref) => Stream.value(true)),
    ];
