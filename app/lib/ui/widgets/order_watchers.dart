import '../../models/order.dart';

/// Detects what changed between two snapshots of the order list, for alerts.
class OrderChanges {
  OrderChanges(List<Order> previous, List<Order> next) {
    final before = {for (final order in previous) order.id: order};
    for (final order in next) {
      final old = before[order.id];
      if (old == null) {
        created.add(order);
        continue;
      }
      if (old.status != order.status) statusChanged.add((from: old.status, order: order));
      final oldItems = {for (final item in old.items) item.id: item};
      final added = [
        for (final item in order.activeItems)
          if (!oldItems.containsKey(item.id)) item,
      ];
      final removed = [
        for (final item in order.items)
          if (item.isCancelled && !(oldItems[item.id]?.isCancelled ?? false)) item,
      ];
      if (added.isNotEmpty) itemsAdded.add((order: order, items: added));
      if (removed.isNotEmpty) itemsRemoved.add((order: order, items: removed));
    }
  }

  final created = <Order>[];
  final statusChanged = <({OrderStatus from, Order order})>[];

  /// Dishes added to / removed from orders already sent (the kitchen must notice both).
  final itemsAdded = <({Order order, List<OrderItem> items})>[];
  final itemsRemoved = <({Order order, List<OrderItem> items})>[];

  Iterable<Order> becameReady() =>
      statusChanged.where((change) => change.order.status == OrderStatus.ready).map((c) => c.order);

  /// Cancelled while the kitchen had it queued or on the stove.
  Iterable<Order> cancelledInKitchen() => statusChanged
      .where(
        (change) =>
            change.order.status == OrderStatus.cancelled &&
            (change.from == OrderStatus.pending || change.from == OrderStatus.inPreparation),
      )
      .map((change) => change.order);
}
