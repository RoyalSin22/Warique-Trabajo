import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alerts.dart';
import '../../models/order.dart';
import '../../state/orders.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/order_watchers.dart';
import 'new_order_page.dart';
import 'order_detail_page.dart';

class WaiterOrdersPage extends ConsumerStatefulWidget {
  const WaiterOrdersPage({super.key});

  @override
  ConsumerState<WaiterOrdersPage> createState() => _WaiterOrdersPageState();
}

class _WaiterOrdersPageState extends ConsumerState<WaiterOrdersPage> {
  bool _onlyPending = true;

  /// Web: the browser keeps sound off until the page is touched; without this the first "Listo"
  /// would be silent (iPhone above all).
  late bool _soundLocked = ref.read(alertsProvider).needsUserGesture;

  /// Must run inside the tap: that is what lets the browser play sound later.
  void _unlockSound() {
    ref.read(alertsProvider).play(AlertTone.ready);
    setState(() => _soundLocked = false);
  }

  /// Any tap on the page unlocks it too (a listener in device_web.dart); re-check right after.
  void _recheckSound() {
    if (!_soundLocked) return;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _soundLocked = ref.read(alertsProvider).needsUserGesture);
    });
  }

  Future<void> _refresh() async {
    try {
      await ref.read(ordersProvider.notifier).refresh();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _newOrder() async {
    final created = await Navigator.of(
      context,
    ).push<Order>(MaterialPageRoute(builder: (_) => const NewOrderPage()));
    if (created == null || !mounted) return;
    ref.read(ordersProvider.notifier).upsert(created);
    showInfoSnack(context, 'Pedido #${created.id} enviado a cocina');
  }

  void _openDetail(Order order) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailPage(orderId: order.id)));

  @override
  Widget build(BuildContext context) {
    // Waiters only see the "ready" alert; the change itself is already on screen.
    // Only the phone of who took the order rings and vibrates; the rest just see the message.
    ref.listen(ordersProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before == null || after == null) return;
      final ready = OrderChanges(before, after).becameReady().toList();
      if (ready.isEmpty) return;
      final myId = ref.read(currentUserProvider).id;
      if (ready.any((order) => order.waiterId == myId)) {
        ref.read(alertsProvider).play(AlertTone.ready, vibrate: true);
      }
      // One snack: several at once (e.g. after reconnecting) would hide each other
      showInfoSnack(
        context,
        ready.map((order) => '¡Listo para entregar! #${order.id} · ${order.target}').join('\n'),
      );
    });

    final orders = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos de hoy'),
        actions: [
          const ConnectionIndicator(),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
          const LogoutButton(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Por atender'), icon: Icon(Icons.pending_actions)),
                ButtonSegment(value: false, label: Text('Todos'), icon: Icon(Icons.list)),
              ],
              selected: {_onlyPending},
              onSelectionChanged: (selection) => setState(() => _onlyPending = selection.first),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newOrder,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo pedido'),
      ),
      body: Listener(
        onPointerUp: (_) => _recheckSound(),
        child: Column(
          children: [
            if (_soundLocked)
              MaterialBanner(
                leading: const Icon(Icons.volume_off),
                content: const Text(
                  'Toca "Activar" para que suene cuando la cocina marque tus pedidos listos.',
                ),
                actions: [
                  FilledButton.icon(
                    onPressed: _unlockSound,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Activar'),
                  ),
                ],
              ),
            Expanded(
              child: switch (orders) {
                AsyncValue(value: final list?) => RefreshIndicator(
                  onRefresh: _refresh,
                  child: _onlyPending
                      ? _PendingSections(orders: list, onTap: _openDetail)
                      : _OrderList(orders: list.reversed.toList(), onTap: _openDetail),
                ),
                AsyncError(:final error) => ErrorRetryView(
                  error: error,
                  onRetry: () => ref.invalidate(ordersProvider),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingSections extends StatelessWidget {
  const _PendingSections({required this.orders, required this.onTap});

  final List<Order> orders;
  final void Function(Order) onTap;

  @override
  Widget build(BuildContext context) {
    final ready = orders.where((o) => o.status == OrderStatus.ready).toList();
    final inKitchen = orders
        .where((o) => o.status == OrderStatus.pending || o.status == OrderStatus.inPreparation)
        .toList();
    final toCollect = orders
        .where((o) => o.status == OrderStatus.delivered && o.paymentStatus != PaymentStatus.paid)
        .toList();

    if (ready.isEmpty && inKitchen.isEmpty && toCollect.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          EmptyView(icon: Icons.check_circle_outline, message: 'Nada pendiente por ahora'),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (ready.isNotEmpty) ...[
          _SectionHeader('Listos para entregar', ready.length, Colors.green),
          for (final order in ready) _OrderTile(order: order, onTap: onTap),
        ],
        if (toCollect.isNotEmpty) ...[
          _SectionHeader('Por cobrar', toCollect.length, Colors.red),
          for (final order in toCollect) _OrderTile(order: order, onTap: onTap),
        ],
        if (inKitchen.isNotEmpty) ...[
          _SectionHeader('En cocina', inKitchen.length, Colors.blue),
          for (final order in inKitchen) _OrderTile(order: order, onTap: onTap),
        ],
      ],
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders, required this.onTap});

  final List<Order> orders;
  final void Function(Order) onTap;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          EmptyView(icon: Icons.receipt_long, message: 'Aún no hay pedidos hoy'),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: orders.length,
      itemBuilder: (context, index) => _OrderTile(order: orders[index], onTap: onTap),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.count, this.color);

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Text('$title ($count)', style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});

  final Order order;
  final void Function(Order) onTap;

  @override
  Widget build(BuildContext context) {
    final summary = order.activeItems.map((item) => '${item.quantity}× ${item.dishName}').join(', ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: () => onTap(order),
        title: Text('#${order.id} · ${order.target}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                StatusChip(order.status),
                if (order.status != OrderStatus.cancelled) PaymentChip(order.paymentStatus),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(order.total.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(timeLabel(order.createdAt), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
