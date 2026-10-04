import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../models/inventory.dart';
import '../../state/inventory.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/text_controllers.dart';
import 'admin_widgets.dart';

/// Cash count (arqueo): open with the change fund, close with what is in the drawer.
/// Expected = fund + cash collected - expenses paid from the drawer.
class CashCard extends ConsumerWidget {
  const CashCard({super.key, required this.date});

  /// Business day `YYYY-MM-DD`.
  final String date;

  Future<void> _open(BuildContext context, WidgetRef ref, CashDay day) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => WithTextControllers(
        initialTexts: [day.session?.openingAmount.plain],
        builder: (dialogContext, controllers) => FormDialog(
          title: day.session == null ? 'Abrir caja' : 'Corregir fondo inicial',
          onSave: () => runSaving(
            dialogContext,
            () => ref.read(inventoryRepositoryProvider).openCash(date, Money.parse(controllers.single.text)),
          ),
          children: [
            const Text(
              'Efectivo que hay en la caja antes del primer cliente. Si sacas dinero para el mercado, '
              'cuenta ANTES de sacarlo y registra la compra en Gastos con "Caja".',
            ),
            TextFormField(
              controller: controllers.single,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Fondo de cambio', prefixText: 'S/ '),
              validator: (value) => _validateMoney(value),
            ),
          ],
        ),
      ),
    );
    if (saved == true) ref.invalidate(cashDayProvider(date));
  }

  Future<void> _close(BuildContext context, WidgetRef ref, CashDay day) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => WithTextControllers(
        initialTexts: [null, day.session?.notes],
        builder: (dialogContext, controllers) {
          final [counted, notes] = controllers;
          return FormDialog(
            title: 'Cerrar caja',
            onSave: () => runSaving(
              dialogContext,
              () => ref
                  .read(inventoryRepositoryProvider)
                  .closeCash(date, Money.parse(counted.text), notes: notes.text),
            ),
            children: [
              // The expected amount is not shown here on purpose: count first, compare after
              const Text('Cuenta billetes y monedas de la caja e ingresa el total.'),
              TextFormField(
                controller: counted,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Efectivo contado', prefixText: 'S/ '),
                validator: (value) => _validateMoney(value),
              ),
              TextFormField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Observación', hintText: 'Opcional'),
                maxLength: 255,
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) ref.invalidate(cashDayProvider(date));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cash = ref.watch(cashDayProvider(date));
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: switch (cash) {
          AsyncValue(value: final day?) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.point_of_sale),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Arqueo de caja', style: theme.textTheme.titleMedium)),
                  if (day.session?.isClosed ?? false) _DifferenceBadge(difference: day.session!.difference!),
                ],
              ),
              const SizedBox(height: 8),
              if (day.session == null) ...[
                const Text('Registra el fondo de cambio para saber cuánto efectivo debe haber al cerrar.'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _open(context, ref, day),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Abrir caja'),
                  ),
                ),
              ] else
                ..._sessionRows(context, ref, day),
            ],
          ),
          AsyncError(:final error) => Row(
            children: [
              Expanded(child: Text('Arqueo: ${errorMessage(error)}')),
              IconButton(
                onPressed: () => ref.invalidate(cashDayProvider(date)),
                icon: const Icon(Icons.refresh),
                tooltip: 'Reintentar',
              ),
            ],
          ),
          _ => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }

  List<Widget> _sessionRows(BuildContext context, WidgetRef ref, CashDay day) {
    final session = day.session!;
    final theme = Theme.of(context);
    final closed = session.isClosed;
    // Payments or expenses registered after closing: the snapshot no longer matches
    final stale = closed && session.expectedAmount != day.expected;
    return [
      _AmountRow('Fondo inicial', day.openingAmount, onEdit: closed ? null : () => _open(context, ref, day)),
      _AmountRow('+ Cobros en efectivo', day.cashSales),
      _AmountRow('− Gastos pagados con caja', day.cashExpenses),
      const Divider(),
      _AmountRow('Debe haber', closed ? session.expectedAmount! : day.expected, bold: true),
      if (closed) ...[
        _AmountRow('Contado', session.countedAmount!, bold: true),
        if (session.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Obs.: ${session.notes}', style: theme.textTheme.bodySmall),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Cerró ${session.closedBy} a las ${timeLabel(session.closedAt!)}.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (stale)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Hubo cobros o gastos después del cierre: ahora debería haber ${day.expected}. '
              'Vuelve a contar.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: closed
            ? OutlinedButton.icon(
                onPressed: () => _close(context, ref, day),
                icon: const Icon(Icons.replay),
                label: const Text('Volver a contar'),
              )
            : FilledButton.icon(
                onPressed: () => _close(context, ref, day),
                icon: const Icon(Icons.lock),
                label: const Text('Cerrar caja'),
              ),
      ),
    ];
  }
}

String? _validateMoney(String? value) {
  final money = Money.tryParse(value);
  if (money == null || money.cents < 0) return 'Monto no válido';
  if (money.cents > 9999999) return 'Máximo S/ 99,999.99';
  return null;
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.amount, {this.bold = false, this.onEdit});

  final String label;
  final Money amount;
  final bool bold;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, size: 18),
              tooltip: 'Corregir fondo',
              visualDensity: VisualDensity.compact,
            ),
          Text(amount.toString(), style: style),
        ],
      ),
    );
  }
}

/// Icon + words, never color alone: "Cuadra", "Faltan S/ 5.00", "Sobran S/ 2.00".
class _DifferenceBadge extends StatelessWidget {
  const _DifferenceBadge({required this.difference});

  final Money difference;

  @override
  Widget build(BuildContext context) {
    final (icon, label, background, foreground) = switch (difference.cents) {
      0 => (Icons.check_circle, 'Cuadra', Colors.green.shade50, Colors.green.shade900),
      < 0 => (
        Icons.error,
        'Faltan ${Money(-difference.cents)}',
        Theme.of(context).colorScheme.errorContainer,
        Theme.of(context).colorScheme.onErrorContainer,
      ),
      _ => (Icons.info, 'Sobran $difference', Colors.amber.shade100, Colors.brown.shade900),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
