import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/money.dart';
import '../../models/order.dart';
import '../../state/session.dart';
import '../widgets/common.dart';

/// Registers one payment (cash, Yape or Plin). Pops with the updated [Order].
/// Mixed payments are several calls: e.g. S/ 20 Yape now, the rest in cash afterwards.
class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({super.key, required this.order, required this.balance});

  final Order order;
  final Money balance;

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  PaymentMethod _method = PaymentMethod.cash;
  late final _amountController = TextEditingController(text: widget.balance.plain)
    ..addListener(_paymentChanged);
  late final _receivedController = TextEditingController()..addListener(_paymentChanged);
  late final _operationController = TextEditingController()..addListener(_paymentChanged);
  bool _submitting = false;

  /// Idempotency key: a retry of the same payment after a timeout is never registered twice.
  /// Any change to the form makes it a different payment.
  String? _requestId;

  void _paymentChanged() => _requestId = null;

  static final _operationPattern = RegExp(r'^[A-Za-z0-9-]{4,30}$'); // same as CreatePaymentDto
  static final _moneyInput = FilteringTextInputFormatter.allow(RegExp(r'^\d{0,5}([.,]\d{0,2})?'));

  @override
  void dispose() {
    _amountController.dispose();
    _receivedController.dispose();
    _operationController.dispose();
    super.dispose();
  }

  Money? get _amount => Money.tryParse(_amountController.text);
  Money? get _received => Money.tryParse(_receivedController.text);

  String? _validateAmount(String? _) {
    final amount = _amount;
    if (amount == null || !amount.isPositive) return 'Monto inválido';
    if (amount > widget.balance) return 'Máximo ${widget.balance}';
    return null;
  }

  String? _validateReceived(String? _) {
    final received = _received;
    final amount = _amount;
    if (received == null) return 'Ingresa con cuánto paga';
    if (amount != null && received < amount) return 'No alcanza para $amount';
    return null;
  }

  String? _validateOperation(String? value) =>
      _operationPattern.hasMatch((value ?? '').trim()) ? null : 'Entre 4 y 30 letras o dígitos';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    _requestId ??= newRequestId();
    try {
      final updated = await ref
          .read(ordersRepositoryProvider)
          .registerPayment(
            widget.order.id,
            method: _method,
            amount: _amount!,
            amountReceived: _method == PaymentMethod.cash ? _received : null,
            operationNumber: _method == PaymentMethod.cash ? null : _operationController.text,
            requestId: _requestId,
          );
      if (mounted) Navigator.pop(context, updated);
    } catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        showErrorSnack(context, error);
      }
    }
  }

  void _setReceived(Money value) => setState(() => _receivedController.text = value.plain);

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    final received = _received;
    final change = amount != null && received != null && received >= amount ? received - amount : null;
    final bills = [10, 20, 50, 100, 200].map((soles) => Money(soles * 100));

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cobrar #${widget.order.id} · ${widget.order.target}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('Saldo pendiente: ${widget.balance}'),
              const SizedBox(height: 12),
              SegmentedButton<PaymentMethod>(
                segments: [
                  for (final method in PaymentMethod.values)
                    ButtonSegment(value: method, label: Text(method.label)),
                ],
                selected: {_method},
                onSelectionChanged: (selection) => setState(() {
                  _method = selection.first;
                  _paymentChanged();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_moneyInput],
                decoration: const InputDecoration(labelText: 'Monto a cobrar', prefixText: 'S/ '),
                validator: _validateAmount,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              if (_method == PaymentMethod.cash) ...[
                TextFormField(
                  controller: _receivedController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_moneyInput],
                  decoration: const InputDecoration(labelText: 'Paga con', prefixText: 'S/ '),
                  validator: _validateReceived,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    if (amount != null && amount.isPositive)
                      ActionChip(label: const Text('Exacto'), onPressed: () => _setReceived(amount)),
                    for (final bill in bills)
                      if (amount == null || bill >= amount)
                        ActionChip(
                          label: Text('S/ ${bill.cents ~/ 100}'),
                          onPressed: () => _setReceived(bill),
                        ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Vuelto')),
                        Text(change?.toString() ?? '—', style: Theme.of(context).textTheme.headlineSmall),
                      ],
                    ),
                  ),
                ),
              ] else
                TextFormField(
                  controller: _operationController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'N.° de operación ${_method.label}',
                    helperText: 'Cópialo de la pantalla del cliente. El dueño lo concilia al cierre.',
                  ),
                  validator: _validateOperation,
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: _submitting
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.payments),
                label: Text('Registrar ${amount?.toString() ?? ''}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
