import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../models/inventory.dart';
import '../../state/inventory.dart';
import '../widgets/common.dart';

/// Every stock change of one supply with the resulting stock: explains each number on screen.
class SupplyHistoryPage extends ConsumerWidget {
  const SupplyHistoryPage({super.key, required this.supplyId});

  final int supplyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(supplyMovementsProvider(supplyId));
    return Scaffold(
      appBar: AppBar(title: Text(history.value?.supply.name ?? 'Historial')),
      body: switch (history) {
        AsyncValue(value: final data?) => _History(supply: data.supply, movements: data.movements),
        AsyncError(:final error) => ErrorRetryView(
          error: error,
          onRetry: () => ref.invalidate(supplyMovementsProvider(supplyId)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.supply, required this.movements});

  final Supply supply;
  final List<SupplyMovement> movements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        ListTile(
          title: const Text('Stock actual'),
          trailing: Text(supply.amount(supply.stock), style: theme.textTheme.titleLarge),
        ),
        const Divider(height: 1),
        if (movements.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('Sin movimientos todavía.'))
        else
          for (final movement in movements)
            ListTile(
              leading: Icon(switch (movement.type) {
                MovementType.purchase => Icons.shopping_basket_outlined,
                MovementType.count => Icons.fact_check_outlined,
                MovementType.waste => Icons.delete_outline,
                MovementType.use => Icons.outdoor_grill_outlined,
                MovementType.voided => Icons.undo,
              }),
              title: Text('${movement.type.label} · ${movement.quantity.signed} ${supply.unit.short}'),
              subtitle: Text(
                [
                  '${mediumDayLabel(movement.createdAt)} ${timeLabel(movement.createdAt)} · ${movement.createdBy}',
                  if (movement.note != null) movement.note!,
                ].join('\n'),
              ),
              trailing: Text('Quedó ${supply.amount(movement.stockAfter)}', style: theme.textTheme.bodySmall),
            ),
      ],
    );
  }
}
