import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/money.dart';
import '../../models/order.dart';
import '../../models/user.dart';
import '../../state/orders.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import 'new_order_page.dart';
import 'payment_sheet.dart';

class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  /// Fallback when the order is not in today's list (e.g. opened after midnight).
  Order? _loaded;
  Object? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await ref.read(ordersProvider.notifier).loadDetail(widget.orderId);
      if (mounted) {
        setState(() {
          _loaded = order;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _run(
    Future<Order> Function() action,
    String successMessage, {
    String Function(Order updated)? successMessageOf,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      ref.read(ordersProvider.notifier).upsert(updated);
      if (mounted) {
        setState(() => _loaded = updated);
        showInfoSnack(context, successMessageOf?.call(updated) ?? successMessage);
      }
    } on ApiException catch (error) {
      if (mounted) showErrorSnack(context, error);
      if (error.isConflict || error.statusCode == 400) await _load(); // show the current state
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newRoundFor(Order order) async {
    final created = await Navigator.of(context).push<Order>(
      MaterialPageRoute(
        builder: (_) => NewOrderPage(
          initialType: order.orderType,
          initialTableId: order.tableId,
          initialCustomerName: order.customerName,
        ),
      ),
    );
    if (created == null || !mounted) return;
    ref.read(ordersProvider.notifier).upsert(created);
    showInfoSnack(context, 'Pedido #${created.id} enviado a cocina');
  }

  Future<void> _changeStatus(Order order, OrderStatus to) => _run(
    () => ref.read(ordersRepositoryProvider).changeStatus(order.id, to),
    'Pedido #${order.id}: ${to.label}',
  );

  Future<void> _cancel(Order order) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Cancelar pedido',
        hint: 'Ej.: el cliente se retiró',
        confirmLabel: 'Cancelar pedido',
        maxLength: 255,
      ),
    );
    if (reason == null) return;
    await _run(
      () => ref
          .read(ordersRepositoryProvider)
          .changeStatus(order.id, OrderStatus.cancelled, cancelReason: reason),
      'Pedido #${order.id} cancelado',
    );
  }

  /// Owner only: a payment registered by mistake (wrong method, amount or order).
  Future<void> _voidPayment(Order order, Payment payment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Anular cobro',
        message:
            '${payment.method.label} · ${payment.amount}\n'
            'Deja de contar en la caja y en los reportes; el pedido vuelve a quedar con saldo.',
        hint: 'Ej.: era Yape, no efectivo',
        confirmLabel: 'Anular cobro',
        maxLength: 150, // VoidPaymentDto
      ),
    );
    if (reason == null) return;
    await _run(
      () => ref.read(ordersRepositoryProvider).voidPayment(order.id, payment.id, reason),
      'Cobro anulado',
      successMessageOf: (updated) => 'Cobro anulado. Saldo: ${updated.balance ?? '—'}',
    );
  }

  Future<void> _pay(Order order, Money balance) async {
    final updated = await showModalBottomSheet<Order>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaymentSheet(order: order, balance: balance),
    );
    if (updated == null || !mounted) return;
    ref.read(ordersProvider.notifier).upsert(updated);
    setState(() => _loaded = updated);
    showInfoSnack(
      context,
      updated.paymentStatus == PaymentStatus.paid
          ? 'Pedido #${order.id} pagado'
          : 'Pago registrado. Saldo: ${updated.balance ?? '—'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(orderByIdProvider(widget.orderId));
    final order = _pickNewest(live, _loaded);
    final role = ref.watch(currentUserProvider).role;

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Pedido #${widget.orderId}')),
        body: _loadError == null
            ? const Center(child: CircularProgressIndicator())
            : ErrorRetryView(error: _loadError!, onRetry: _load),
      );
    }

    final balance = order.balance;
    final nextSteps = [
      for (final to in [OrderStatus.inPreparation, OrderStatus.ready, OrderStatus.delivered])
        if (order.canTransition(to, role)) to,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${order.id}'),
        actions: [
          const ConnectionIndicator(),
          // Orders cannot be edited once in the kitchen: a second round is a new order, same target
          if (role != Role.kitchen && order.status != OrderStatus.cancelled)
            IconButton(
              onPressed: () => _newRoundFor(order),
              icon: const Icon(Icons.add_shopping_cart),
              tooltip: order.orderType == OrderType.dineIn
                  ? 'Otro pedido para esta mesa'
                  : 'Otro pedido para este cliente',
            ),
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(order.target, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('${timeLabel(order.createdAt)} · ${order.waiterName}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              StatusChip(order.status),
              if (order.status != OrderStatus.cancelled) PaymentChip(order.paymentStatus),
            ],
          ),
          if (order.cancelReason != null) ...[
            const SizedBox(height: 8),
            Text(
              'Motivo de cancelación: ${order.cancelReason}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Divider(height: 24),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 36,
                    child: Text('${item.quantity}×', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.dishName),
                        if (item.notes != null)
                          Text(
                            item.notes!,
                            style: TextStyle(color: Colors.amber.shade900, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                  Text(item.subtotal.toString()),
                ],
              ),
            ),
          if (order.notes != null) ...[
            const SizedBox(height: 8),
            Text('Nota: ${order.notes}', style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
          const Divider(height: 24),
          _AmountRow('Total', order.total, bold: true),
          if (order.payments != null) ...[
            _AmountRow('Pagado', order.paid),
            if (balance != null) _AmountRow('Saldo', balance, bold: balance.isPositive),
            const SizedBox(height: 8),
            for (final payment in order.payments!)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  payment.isVoid
                      ? Icons.block
                      : payment.method == PaymentMethod.cash
                      ? Icons.payments
                      : Icons.qr_code_2,
                  color: payment.isVoid ? Theme.of(context).colorScheme.outline : null,
                ),
                title: Text(
                  '${payment.method.label} · ${payment.amount}',
                  style: payment.isVoid
                      ? TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Theme.of(context).colorScheme.outline,
                        )
                      : null,
                ),
                subtitle: Text(
                  [
                    timeLabel(payment.createdAt),
                    if (payment.amountReceived != null) 'recibido ${payment.amountReceived}',
                    if (payment.changeGiven != null && payment.changeGiven!.isPositive)
                      'vuelto ${payment.changeGiven}',
                    if (payment.operationNumber != null) 'op. ${payment.operationNumber}',
                    if (payment.isVoid) 'ANULADO: ${payment.voidReason}',
                  ].join(' · '),
                ),
                trailing: role == Role.owner && !payment.isVoid
                    ? IconButton(
                        tooltip: 'Anular cobro',
                        icon: const Icon(Icons.undo),
                        onPressed: _busy ? null : () => _voidPayment(order, payment),
                      )
                    : null,
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (order.canCancel(role))
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _cancel(order),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar'),
                ),
              for (final to in nextSteps)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _changeStatus(order, to),
                  icon: Icon(to == OrderStatus.delivered ? Icons.room_service : Icons.soup_kitchen),
                  label: Text(switch (to) {
                    OrderStatus.inPreparation => 'Iniciar preparación',
                    OrderStatus.ready => 'Marcar listo',
                    _ => 'Entregar',
                  }),
                ),
              if (order.canReceivePayment && role != Role.kitchen)
                FilledButton.icon(
                  // Balance unknown until payments load (only for partially paid orders)
                  onPressed: _busy || balance == null ? null : () => _pay(order, balance),
                  icon: const Icon(Icons.point_of_sale),
                  label: Text('Cobrar ${balance ?? ''}'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The live copy may lack payments; the loaded one may be stale. Prefer newest, then richest.
  static Order? _pickNewest(Order? live, Order? loaded) {
    if (live == null) return loaded;
    if (loaded == null) return live;
    if (live.updatedAt.isAfter(loaded.updatedAt)) return live;
    if (loaded.updatedAt.isAfter(live.updatedAt)) return loaded;
    return live.payments != null ? live : loaded;
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.amount, {this.bold = false});

  final String label;
  final Money amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(amount.toString(), style: style),
        ],
      ),
    );
  }
}

/// Asks for the reason of a destructive action (cancel an order, void a payment).
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.maxLength,
    this.message,
  });

  final String title;
  final String? message;
  final String hint;
  final String confirmLabel;
  final int maxLength;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().length >= 3; // UpdateOrderStatusDto: MinLength(3)

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          decoration: InputDecoration(labelText: 'Motivo', hintText: widget.hint),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
      FilledButton(
        onPressed: _valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
