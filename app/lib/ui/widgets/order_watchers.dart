import '../../models/order.dart';

/// Detects what changed between two snapshots of the order list, for alerts.
class OrderChanges {
  OrderChanges(List<Order> previous, List<Order> next) {
    final before = {for (final order in previous) order.id: order};
    for (final order in next) {
      final old = before[order.id];
      if (old == null) {
        created.add(order);
      } else if (old.status != order.status) {
        statusChanged.add((from: old.status, order: order));
      }
    }
  }

  final created = <Order>[];
  final statusChanged = <({OrderStatus from, Order order})>[];

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
