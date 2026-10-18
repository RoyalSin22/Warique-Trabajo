import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime_client.dart';
import '../models/order.dart';
import 'realtime.dart';
import 'session.dart';

/// Today's orders, kept in sync with `order.created` / `order.updated` events.
/// Every reconnection triggers a full reload so events missed while offline are recovered.
final ordersProvider = AsyncNotifierProvider.autoDispose<OrdersNotifier, List<Order>>(OrdersNotifier.new);

class OrdersNotifier extends AsyncNotifier<List<Order>> {
  @override
  Future<List<Order>> build() async {
    final realtime = ref.watch(realtimeClientProvider);
    final subscriptions = <StreamSubscription<Object?>>[
      realtime.messages.listen(_onMessage),
      realtime.connected.where((isConnected) => isConnected).listen((_) => _refreshQuietly()),
    ];
    // A tablet left on overnight must not show yesterday's queue: reload when the day changes.
    // Coming back to the app (screen unlocked, app switched) reloads too; a token that expired
    // meanwhile gets a 401 there and goes to the login screen before anyone taps a button.
    var day = _dayKey(DateTime.now());
    final dayWatch = Timer.periodic(const Duration(minutes: 1), (_) {
      final today = _dayKey(DateTime.now());
      if (today == day) return;
      day = today;
      _refreshQuietly();
    });
    final lifecycle = AppLifecycleListener(onResume: _refreshQuietly);
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      dayWatch.cancel();
      lifecycle.dispose();
    });
    _buffer.clear();
    final orders = await ref.watch(ordersRepositoryProvider).today();
    // Events that arrived while the request was in flight may be newer than the response
    return _buffer.fold<List<Order>>(orders, _merged);
  }

  final _buffer = <Order>[];

  void _onMessage(RealtimeMessage message) {
    if (message.event != RealtimeEvent.orderCreated && message.event != RealtimeEvent.orderUpdated) {
      return;
    }
    final payload = message.payload;
    if (payload is Map<String, dynamic>) upsert(Order.fromJson(payload));
  }

  void upsert(Order order) {
    final current = state.value;
    if (current == null || state.isLoading) {
      _buffer.add(order);
      if (current == null) return;
    }
    state = AsyncData(_merged(current, order));
  }

  /// Inserts or replaces by id, keeping FIFO order (oldest first, like the API).
  static List<Order> _merged(List<Order> current, Order order) {
    final index = current.indexWhere((existing) => existing.id == order.id);
    if (index == -1) {
      return [...current, order]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    // Out-of-order events: never replace a newer copy with an older one
    if (order.updatedAt.isBefore(current[index].updatedAt)) return current;
    return [...current]..[index] = current[index].mergeWith(order);
  }

  void _refreshQuietly() => refresh().catchError((Object _) {});

  static String _dayKey(DateTime time) => '${time.year}-${time.month}-${time.day}';

  Future<void> refresh() async {
    try {
      final startedAt = DateTime.now();
      final orders = await ref.read(ordersRepositoryProvider).today();
      if (!ref.mounted) return;
      final previous = {for (final order in state.value ?? const <Order>[]) order.id: order};
      final fromServer = {for (final order in orders) order.id};
      state = AsyncData(
        [
          for (final order in orders)
            switch (previous[order.id]) {
              // An event (e.g. "Listo" just tapped) newer than this snapshot wins
              final known? when known.updatedAt.isAfter(order.updatedAt) => known,
              final known? => known.mergeWith(order),
              null => order,
            },
          // Created by an event while the request was in flight: not in the snapshot yet
          for (final order in previous.values)
            if (!fromServer.contains(order.id) && !order.createdAt.isBefore(startedAt)) order,
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );
    } catch (error, stack) {
      if (!ref.mounted) return;
      // Keep showing the last known list; only surface the error when there is nothing to show
      if (state.value == null) state = AsyncError(error, stack);
      rethrow;
    }
  }

  /// Loads payments (only the detail endpoint includes them).
  Future<Order> loadDetail(int id) async {
    final order = await ref.read(ordersRepositoryProvider).byId(id);
    if (ref.mounted) upsert(order);
    return order;
  }
}

/// Single order from the shared list, so the detail screen updates live.
final orderByIdProvider = Provider.autoDispose.family<Order?, int>((ref, id) {
  final orders = ref.watch(ordersProvider).value ?? const <Order>[];
  for (final order in orders) {
    if (order.id == id) return order;
  }
  return null;
});
