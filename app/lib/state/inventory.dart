import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime_client.dart';
import '../models/inventory.dart';
import '../models/user.dart';
import 'realtime.dart';
import 'session.dart';

/// Supplies with their stock, low stock first; kept in sync with `supply.updated` so the owner
/// sees the kitchen's counts (and the kitchen sees the owner's purchases) without reloading.
/// The owner also gets deactivated supplies.
final suppliesProvider = AsyncNotifierProvider.autoDispose<SuppliesNotifier, List<Supply>>(
  SuppliesNotifier.new,
);

class SuppliesNotifier extends AsyncNotifier<List<Supply>> {
  bool get _includeInactive => ref.read(currentUserProvider).role == Role.owner;

  @override
  Future<List<Supply>> build() async {
    final realtime = ref.watch(realtimeClientProvider);
    final subscriptions = <StreamSubscription<Object?>>[
      realtime.messages.where((message) => message.event == RealtimeEvent.supplyUpdated).listen(_onUpdated),
      realtime.connected.where((isConnected) => isConnected).listen((_) => refresh()),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });
    return sortSupplies(
      await ref.watch(inventoryRepositoryProvider).supplies(includeInactive: _includeInactive),
    );
  }

  void _onUpdated(RealtimeMessage message) {
    final payload = message.payload;
    if (payload is Map<String, dynamic>) upsert(Supply.fromJson(payload));
  }

  /// Applies a supply returned by the API or pushed by the server.
  void upsert(Supply supply) {
    final current = state.value;
    if (current == null) return;
    final index = current.indexWhere((existing) => existing.id == supply.id);
    final next = [...current];
    if (index == -1) {
      next.add(supply);
    } else {
      next[index] = supply;
    }
    if (!_includeInactive) next.removeWhere((s) => !s.isActive);
    state = AsyncData(sortSupplies(next));
  }

  Future<void> refresh() async {
    try {
      final supplies = await ref
          .read(inventoryRepositoryProvider)
          .supplies(includeInactive: _includeInactive);
      if (ref.mounted) state = AsyncData(sortSupplies(supplies));
    } catch (_) {
      // Keep the current list; the next event or reconnection retries
    }
  }
}

/// Same order as the server: low stock first, then by name; inactive ones last.
List<Supply> sortSupplies(List<Supply> supplies) => [...supplies]
  ..sort((a, b) {
    if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
    if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// Active supplies at or under their minimum: the badge on the Insumos / Gestión tabs.
final lowSupplyCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(suppliesProvider).value?.where((s) => s.isActive && s.isLow).length ?? 0,
);

final supplyMovementsProvider = FutureProvider.autoDispose
    .family<({Supply supply, List<SupplyMovement> movements}), int>(
      (ref, supplyId) => ref.watch(inventoryRepositoryProvider).movements(supplyId),
    );

/// Keyed by business day `YYYY-MM-DD`.
final expensesProvider = FutureProvider.autoDispose.family<ExpenseDay, String>(
  (ref, date) => ref.watch(inventoryRepositoryProvider).expenses(date),
);

/// Keyed by business day `YYYY-MM-DD`.
final cashDayProvider = FutureProvider.autoDispose.family<CashDay, String>(
  (ref, date) => ref.watch(inventoryRepositoryProvider).cashDay(date),
);
