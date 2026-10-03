import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime_client.dart';
import 'session.dart';

final realtimeClientProvider = Provider.autoDispose<RealtimeClient>((ref) {
  final session = ref.watch(currentSessionProvider);
  final client = SocketRealtimeClient(serverUrl: session.serverUrl, token: session.token);
  ref.onDispose(client.dispose);
  client.connect();
  return client;
});

/// Live-link indicator. Staff must know when the screen may be out of date.
final realtimeConnectedProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(realtimeClientProvider).connected,
);
