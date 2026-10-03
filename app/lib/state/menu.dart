import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime_client.dart';
import '../models/menu.dart';
import 'realtime.dart';
import 'session.dart';

/// Active menu, kept in sync with `dish.updated` and `dishes.reset`.
final menuProvider = AsyncNotifierProvider.autoDispose<MenuNotifier, List<Dish>>(MenuNotifier.new);

class MenuNotifier extends AsyncNotifier<List<Dish>> {
  @override
  Future<List<Dish>> build() async {
    final realtime = ref.watch(realtimeClientProvider);
    final subscriptions = <StreamSubscription<Object?>>[
      realtime.messages.listen(_onMessage),
      realtime.connected.where((isConnected) => isConnected).listen((_) => _reload()),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });
    return ref.watch(menuRepositoryProvider).dishes();
  }

  void _onMessage(RealtimeMessage message) {
    switch (message.event) {
      case RealtimeEvent.dishUpdated:
        final payload = message.payload;
        if (payload is Map<String, dynamic>) _upsert(Dish.fromJson(payload));
      case RealtimeEvent.dishesReset:
        _reload();
    }
  }

  void _upsert(Dish dish) {
    final current = state.value;
    if (current == null) return;
    final index = current.indexWhere((existing) => existing.id == dish.id);
    // A new dish or a category change alters the server ordering: reload instead of guessing
    if (index == -1 || current[index].category.id != dish.category.id) {
      _reload();
      return;
    }
    final next = [...current];
    if (dish.isActive) {
      next[index] = dish;
    } else {
      next.removeAt(index);
    }
    state = AsyncData(next);
  }

  Future<void> _reload() async {
    try {
      final dishes = await ref.read(menuRepositoryProvider).dishes();
      if (ref.mounted) state = AsyncData(dishes);
    } catch (_) {
      // Keep the current menu; the next event or reconnection retries
    }
  }

  Future<void> setAvailability(Dish dish, bool isAvailable) async {
    final updated = await ref.read(menuRepositoryProvider).setAvailability(dish.id, isAvailable);
    if (ref.mounted) _upsert(updated);
  }

  Future<int> resetAvailability() async {
    final count = await ref.read(menuRepositoryProvider).resetAvailability();
    await _reload();
    return count;
  }

  Future<void> refresh() => _reload();
}

final tablesProvider = FutureProvider.autoDispose((ref) => ref.watch(menuRepositoryProvider).tables());
