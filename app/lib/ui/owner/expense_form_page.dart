import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../models/inventory.dart';
import '../../state/inventory.dart';
import '../../state/session.dart';
import '../inventory/supplies_page.dart' show showSupplyDialog, validateQuantity;
import '../widgets/common.dart';
import 'admin_widgets.dart';

/// New expense. Category "Insumos" can carry supply lines: their costs add up to the total and
/// each quantity enters the stock (the server does both in one transaction).
class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({super.key, required this.day});

  final DateTime day;

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _Line {
  int? supplyId;
  final quantity = TextEditingController();
  final cost = TextEditingController();

  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _lines = <_Line>[];
  var _category = ExpenseCategory.insumos;
  var _paidWith = PaidWith.cash;
  bool _saving = false;

  /// Same key for retries of the same content; any edit makes it a new expense.
  String _requestId = newRequestId();

  void _changed() => _requestId = newRequestId();

  @override
  void initState() {
    super.initState();
    _addLine();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    final line = _Line();
    for (final controller in [line.quantity, line.cost]) {
      controller.addListener(() => setState(_changed));
    }
    setState(() => _lines.add(line));
  }

  void _removeLine(_Line line) {
    setState(() {
      _lines.remove(line);
      _changed();
    });
    // After the frame: the removed fields are still being torn down in this one
    WidgetsBinding.instance.addPostFrameCallback((_) => line.dispose());
  }

  bool get _isPurchase => _category == ExpenseCategory.insumos && _lines.isNotEmpty;

  Money get _linesTotal =>
      _lines.fold(Money.zero, (sum, line) => sum + (Money.tryParse(line.cost.text) ?? Money.zero));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isPurchase && !_linesTotal.isPositive) {
      showErrorSnack(context, 'El total de la compra debe ser mayor que 0');
      return;
    }
    setState(() => _saving = true);
    final ok = await runSaving(
      context,
      () => ref
          .read(inventoryRepositoryProvider)
          .createExpense(
            businessDate: dayKey(widget.day),
            category: _category,
            description: _description.text,
            paidWith: _paidWith,
            amount: _isPurchase ? null : Money.parse(_amount.text),
            items: [
              if (_isPurchase)
                for (final line in _lines)
                  (
                    supplyId: line.supplyId!,
                    quantity: Quantity.parse(line.quantity.text),
                    cost: Money.parse(line.cost.text),
                  ),
            ],
            requestId: _requestId,
          ),
      success: 'Gasto registrado',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supplies = ref.watch(suppliesProvider).value?.where((s) => s.isActive).toList() ?? const <Supply>[];
    final isToday = widget.day == dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: Text(isToday ? 'Nuevo gasto' : 'Gasto del ${shortDayLabel(widget.day)}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            DropdownButtonFormField<ExpenseCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Tipo de gasto'),
              items: [
                for (final c in ExpenseCategory.values)
                  DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [Icon(expenseIcon(c), size: 20), const SizedBox(width: 8), Text(c.label)],
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _category = value ?? _category;
                _changed();
              }),
            ),
            TextFormField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'Descripción',
                hintText: _category == ExpenseCategory.insumos
                    ? 'Ej.: Mercado mayorista'
                    : 'Ej.: Balón de gas 10 kg',
              ),
              maxLength: 150,
              validator: (value) => requiredText(value, max: 150),
              onChanged: (_) => _changed(),
            ),
            const SizedBox(height: 4),
            Text('¿Con qué se pagó?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<PaidWith>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PaidWith.cash, icon: Icon(Icons.point_of_sale), label: Text('Caja')),
                ButtonSegment(
                  value: PaidWith.other,
                  icon: Icon(Icons.account_balance_wallet),
                  label: Text('Otro'),
                ),
              ],
              selected: {_paidWith},
              onSelectionChanged: (s) => setState(() {
                _paidWith = s.first;
                _changed();
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _paidWith == PaidWith.cash
                    ? 'Sale del efectivo de la caja: baja lo que debe haber al cerrar.'
                    : 'Yape, transferencia o dinero de tu bolsillo: no toca la caja.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            if (_category == ExpenseCategory.insumos) ...[
              Row(
                children: [
                  Expanded(child: Text('Insumos comprados', style: theme.textTheme.titleMedium)),
                  TextButton.icon(
                    onPressed: () => showSupplyDialog(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nuevo insumo'),
                  ),
                ],
              ),
              Text(
                _lines.isEmpty
                    ? 'Sin detalle: el gasto no cambia el stock.'
                    : 'Cada cantidad entra al stock. El precio es lo pagado por toda la línea.',
                style: theme.textTheme.bodySmall,
              ),
              for (final (index, line) in _lines.indexed)
                _LineFields(
                  key: ObjectKey(line),
                  line: line,
                  index: index,
                  supplies: supplies,
                  takenIds: {
                    for (final other in _lines)
                      if (other != line) ?other.supplyId,
                  },
                  onSupply: (id) => setState(() {
                    line.supplyId = id;
                    _changed();
                  }),
                  onRemove: () => _removeLine(line),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar otro insumo'),
                ),
              ),
            ],
            if (!_isPurchase)
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto', prefixText: 'S/ '),
                validator: _validateMoney,
                onChanged: (_) => _changed(),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Total de la compra'),
                trailing: Text(_linesTotal.toString(), style: theme.textTheme.titleLarge),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Guardar gasto'),
            ),
          ],
        ),
      ),
    );
  }
}

IconData expenseIcon(ExpenseCategory category) => switch (category) {
  ExpenseCategory.insumos => Icons.shopping_basket_outlined,
  ExpenseCategory.gas => Icons.local_fire_department_outlined,
  ExpenseCategory.servicios => Icons.lightbulb_outline,
  ExpenseCategory.sueldos => Icons.badge_outlined,
  ExpenseCategory.alquiler => Icons.home_work_outlined,
  ExpenseCategory.transporte => Icons.local_shipping_outlined,
  ExpenseCategory.otros => Icons.receipt_outlined,
};

String? _validateMoney(String? value, {bool allowZero = false}) {
  final money = Money.tryParse(value);
  if (money == null || money.cents < 0) return 'Monto no válido';
  if (!allowZero && !money.isPositive) return 'Debe ser mayor que 0';
  if (money.cents > 9999999) return 'Máximo S/ 99,999.99';
  return null;
}

class _LineFields extends StatelessWidget {
  const _LineFields({
    super.key,
    required this.line,
    required this.index,
    required this.supplies,
    required this.takenIds,
    required this.onSupply,
    required this.onRemove,
  });

  final _Line line;
  final int index;
  final List<Supply> supplies;
  final Set<int> takenIds;
  final ValueChanged<int?> onSupply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final supply = supplies.where((s) => s.id == line.supplyId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: supply?.id,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Insumo ${index + 1}'),
                    items: [
                      for (final s in supplies)
                        if (!takenIds.contains(s.id)) DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    validator: (value) => value == null ? 'Elige el insumo' : null,
                    onChanged: onSupply,
                  ),
                ),
                IconButton(onPressed: onRemove, icon: const Icon(Icons.close), tooltip: 'Quitar línea'),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: line.quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Cantidad', suffixText: supply?.unit.short),
                    validator: (value) => supply == null ? null : validateQuantity(value, supply.unit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: line.cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Precio pagado', prefixText: 'S/ '),
                    validator: (value) => _validateMoney(value, allowZero: true),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
