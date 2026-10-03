import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../models/inventory.dart';
import '../../state/admin.dart';
import '../../state/inventory.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/day_navigator.dart';
import '../widgets/text_controllers.dart';
import 'admin_widgets.dart';
import 'expense_form_page.dart';

/// The day's expenses. A wrong one is voided with a reason (never deleted): it stays listed,
/// struck through, and stops counting.
class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key, this.initialDay});

  final DateTime? initialDay;

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  late DateTime _day = widget.initialDay ?? dateOnly(DateTime.now());

  /// Expenses change the Cierre figures and the expected cash of that day.
  void _invalidate() {
    final key = dayKey(_day);
    ref.invalidate(expensesProvider(key));
    ref.invalidate(dailyReportProvider(key));
    ref.invalidate(cashDayProvider(key));
    ref.invalidate(salesSummaryProvider);
  }

  Future<void> _add() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => ExpenseFormPage(day: _day)));
    if (saved == true) _invalidate();
  }

  Future<void> _void(Expense expense) async {
    final voided = await showDialog<bool>(
      context: context,
      builder: (_) => WithTextControllers(
        initialTexts: const [null],
        builder: (dialogContext, controllers) => FormDialog(
          title: 'Anular gasto',
          onSave: () => runSaving(
            dialogContext,
            () => ref.read(inventoryRepositoryProvider).voidExpense(expense.id, controllers.single.text),
          ),
          children: [
            Text(
              '${expense.description} · ${expense.amount}'
              '${expense.items.isEmpty ? '' : '\nSe descontará del stock lo que entró con esta compra.'}',
            ),
            TextFormField(
              controller: controllers.single,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Ej.: lo registré dos veces'),
              validator: (value) => requiredText(value, max: 150),
            ),
          ],
        ),
      ),
    );
    if (voided == true) _invalidate();
  }

  @override
  Widget build(BuildContext context) {
    final key = dayKey(_day);
    final expenses = ref.watch(expensesProvider(key));
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo gasto'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(expensesProvider(key)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          children: [
            DayNavigator(day: _day, onChanged: (day) => setState(() => _day = day)),
            switch (expenses) {
              AsyncValue(value: final data?) => _ExpenseList(data: data, onVoid: _void),
              AsyncError(:final error) => ErrorRetryView(
                error: error,
                onRetry: () => ref.invalidate(expensesProvider(key)),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({required this.data, required this.onVoid});

  final ExpenseDay data;
  final ValueChanged<Expense> onVoid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: EmptyView(icon: Icons.receipt_long_outlined, message: 'Sin gastos este día'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total del día', style: theme.textTheme.labelLarge),
                      Text(data.total.toString(), style: theme.textTheme.headlineSmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Salió de la caja', style: theme.textTheme.labelLarge),
                    Text(data.cashTotal.toString(), style: theme.textTheme.titleLarge),
                  ],
                ),
              ],
            ),
          ),
        ),
        for (final expense in data.expenses)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(expenseIcon(expense.category)),
            title: Text(
              expense.description,
              style: expense.isVoid ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
            ),
            subtitle: Text(
              [
                '${expense.category.label} · ${expense.paidWith.label} · ${timeLabel(expense.createdAt)}',
                for (final item in expense.items)
                  '${item.supplyName}: ${item.quantity} ${item.unit.short} · ${item.cost}',
                if (expense.isVoid) 'ANULADO: ${expense.voidReason}',
              ].join('\n'),
            ),
            isThreeLine: expense.items.isNotEmpty || expense.isVoid,
            trailing: Text(
              expense.amount.toString(),
              style: theme.textTheme.titleMedium?.copyWith(
                decoration: expense.isVoid ? TextDecoration.lineThrough : null,
                color: expense.isVoid ? theme.colorScheme.outline : null,
              ),
            ),
            onLongPress: expense.isVoid ? null : () => onVoid(expense),
            onTap: expense.isVoid ? null : () => onVoid(expense),
          ),
        if (data.expenses.any((e) => !e.isVoid))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Toca un gasto para anularlo.', style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
