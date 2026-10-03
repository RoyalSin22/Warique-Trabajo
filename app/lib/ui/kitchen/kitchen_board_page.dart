import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/order.dart';
import '../../state/orders.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/order_watchers.dart';

/// Kitchen queue, oldest first: "Pendientes" and "En preparación".
/// Two columns on tablets/PC, two tabs on phones.
class KitchenBoardPage extends ConsumerStatefulWidget {
  const KitchenBoardPage({super.key});

  @override
  ConsumerState<KitchenBoardPage> createState() => _KitchenBoardPageState();
}

class _KitchenBoardPageState extends ConsumerState<KitchenBoardPage> {
  /// Minutes after which an order is highlighted as late.
  static const lateAfterMinutes = 20;

  late final Timer _ticker;
  DateTime _now = DateTime.now();
  final _busy = <int>{};
  final _fresh = <int>{};

  @override
  void initState() {
    super.initState();
    // Refreshes "hace N min" without touching the network
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _advance(Order order, OrderStatus to) async {
    setState(() => _busy.add(order.id));
    try {
      final updated = await ref.read(ordersRepositoryProvider).changeStatus(order.id, to);
      ref.read(ordersProvider.notifier).upsert(updated);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
      await ref.read(ordersProvider.notifier).refresh().catchError((Object _) {});
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
    }
  }

  void _onOrdersChanged(List<Order>? before, List<Order>? after) {
    if (before == null || after == null) return;
    final changes = OrderChanges(before, after);
    final created = changes.created.where((o) => o.status == OrderStatus.pending).toList();
    if (created.isNotEmpty) {
      setState(() => _fresh.addAll(created.map((o) => o.id)));
      showInfoSnack(context, 'Nuevo pedido: ${created.map((o) => '#${o.id} ${o.target}').join(', ')}');
    }
    final cancelled = changes.cancelledInKitchen().toList();
    if (cancelled.isNotEmpty) {
      // Critical for the kitchen: stop cooking it
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber, size: 40),
          title: const Text('Pedido cancelado'),
          content: Text(
            [
              for (final order in cancelled)
                '#${order.id} ${order.target}: ${order.items.map((i) => '${i.quantity}× ${i.dishName}').join(', ')}'
                    '${order.cancelReason == null ? '' : '\nMotivo: ${order.cancelReason}'}',
            ].join('\n\n'),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ordersProvider, (previous, next) => _onOrdersChanged(previous?.value, next.value));
    final orders = ref.watch(ordersProvider);
    final role = ref.watch(currentUserProvider).role;

    Widget column(List<Order> list, String empty) => list.isEmpty
        ? EmptyView(icon: Icons.soup_kitchen, message: empty)
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final order = list[index];
              return _KitchenCard(
                order: order,
                now: _now,
                isLate: _now.difference(order.createdAt).inMinutes >= lateAfterMinutes,
                isFresh: _fresh.contains(order.id),
                busy: _busy.contains(order.id),
                onAdvance: switch (order.status) {
                  OrderStatus.pending when order.canTransition(OrderStatus.inPreparation, role) => () {
                    setState(() => _fresh.remove(order.id));
                    _advance(order, OrderStatus.inPreparation);
                  },
                  OrderStatus.inPreparation when order.canTransition(OrderStatus.ready, role) =>
                    () => _advance(order, OrderStatus.ready),
                  _ => null,
                },
              );
            },
          );

    return switch (orders) {
      AsyncValue(value: final list?) => _Layout(
        pending: list.where((o) => o.status == OrderStatus.pending).toList(),
        cooking: list.where((o) => o.status == OrderStatus.inPreparation).toList(),
        readyCount: list.where((o) => o.status == OrderStatus.ready).length,
        column: column,
        onRefresh: () => ref.read(ordersProvider.notifier).refresh().catchError((Object e) {
          if (context.mounted) showErrorSnack(context, e);
        }),
      ),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(title: const Text('Cocina'), actions: const [LogoutButton()]),
        body: ErrorRetryView(error: error, onRetry: () => ref.invalidate(ordersProvider)),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _Layout extends StatelessWidget {
  const _Layout({
    required this.pending,
    required this.cooking,
    required this.readyCount,
    required this.column,
    required this.onRefresh,
  });

  final List<Order> pending;
  final List<Order> cooking;
  final int readyCount;
  final Widget Function(List<Order>, String) column;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final pendingTitle = 'Pendientes (${pending.length})';
    final cookingTitle = 'En preparación (${cooking.length})';
    final actions = [
      if (readyCount > 0)
        Tooltip(
          message: '$readyCount por recoger',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Badge(label: Text('$readyCount'), child: const Icon(Icons.room_service)),
          ),
        ),
      const ConnectionIndicator(),
      IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
      const LogoutButton(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          Widget titled(String title, Widget child) => Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                Expanded(child: child),
              ],
            ),
          );
          return Scaffold(
            appBar: AppBar(title: const Text('Cocina'), actions: actions),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titled(pendingTitle, column(pending, 'Sin pedidos pendientes')),
                const VerticalDivider(width: 1),
                titled(cookingTitle, column(cooking, 'Nada en preparación')),
              ],
            ),
          );
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Cocina'),
              actions: actions,
              bottom: TabBar(
                tabs: [
                  Tab(text: pendingTitle),
                  Tab(text: cookingTitle),
                ],
              ),
            ),
            body: TabBarView(
              children: [column(pending, 'Sin pedidos pendientes'), column(cooking, 'Nada en preparación')],
            ),
          ),
        );
      },
    );
  }
}

class _KitchenCard extends StatelessWidget {
  const _KitchenCard({
    required this.order,
    required this.now,
    required this.isLate,
    required this.isFresh,
    required this.busy,
    required this.onAdvance,
  });

  final Order order;
  final DateTime now;
  final bool isLate;
  final bool isFresh;
  final bool busy;
  final VoidCallback? onAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = order.status == OrderStatus.pending;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isFresh ? BorderSide(color: theme.colorScheme.primary, width: 3) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${order.id} · ${order.target}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(Icons.schedule, size: 16, color: isLate ? theme.colorScheme.error : null),
                const SizedBox(width: 4),
                Text(
                  elapsedLabel(order.createdAt, now),
                  style: TextStyle(
                    color: isLate ? theme.colorScheme.error : null,
                    fontWeight: isLate ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item.quantity} × ${item.dishName}', style: theme.textTheme.titleMedium),
                    // An icon, not a "↳" character: the bundled offline font has no arrow glyphs
                    if (item.notes != null)
                      Row(
                        children: [
                          const SizedBox(width: 8),
                          Icon(Icons.subdirectory_arrow_right, size: 18, color: Colors.amber.shade900),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.notes!,
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            if (order.notes != null) ...[
              const SizedBox(height: 4),
              Text('Nota: ${order.notes}', style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 4),
            Text('Mozo: ${order.waiterName}', style: theme.textTheme.bodySmall),
            if (onAdvance != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : onAdvance,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: isPending ? null : Colors.green.shade700,
                ),
                icon: busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(isPending ? Icons.local_fire_department : Icons.check),
                label: Text(isPending ? 'Empezar' : 'Listo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
