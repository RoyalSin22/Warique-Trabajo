import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Events emitted by `backend/src/realtime/realtime.service.ts`.
abstract final class RealtimeEvent {
  static const orderCreated = 'order.created';
  static const orderUpdated = 'order.updated';
  static const dishUpdated = 'dish.updated';
  static const dishesReset = 'dishes.reset';
}

class RealtimeMessage {
  const RealtimeMessage(this.event, this.payload);

  final String event;
  final Object? payload;
}

/// Live event feed. An interface so tests (and future transports) can replace Socket.IO.
abstract interface class RealtimeClient {
  Stream<RealtimeMessage> get messages;

  /// true on every successful (re)connection, false when the link drops.
  Stream<bool> get connected;

  void connect();

  void dispose();
}

/// Socket.IO connection authenticated with the JWT. Reconnects on its own; every (re)connection
/// is reported through [connected] so listeners can refetch whatever they missed while offline.
class SocketRealtimeClient implements RealtimeClient {
  SocketRealtimeClient({required String serverUrl, required String token}) {
    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );

    _socket
      ..onConnect((_) => _connected.add(true))
      ..onDisconnect((_) => _connected.add(false))
      ..onConnectError((_) => _connected.add(false));

    for (final event in const [
      RealtimeEvent.orderCreated,
      RealtimeEvent.orderUpdated,
      RealtimeEvent.dishUpdated,
      RealtimeEvent.dishesReset,
    ]) {
      _socket.on(event, (payload) => _messages.add(RealtimeMessage(event, payload)));
    }
  }

  late final io.Socket _socket;
  final _messages = StreamController<RealtimeMessage>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  @override
  Stream<RealtimeMessage> get messages => _messages.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  void connect() => _socket.connect();

  @override
  void dispose() {
    _socket.dispose();
    _messages.close();
    _connected.close();
  }
}
