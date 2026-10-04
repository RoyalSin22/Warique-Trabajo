import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/quantity.dart';
import '../../models/inventory.dart';
import '../../state/inventory.dart';
import '../../state/session.dart';
import '../owner/admin_widgets.dart';
import '../widgets/common.dart';
import '../widgets/text_controllers.dart';
import 'supply_history_page.dart';

/// Stock of every supply, low stock first. The kitchen registers counts, waste and use; the owner
/// also creates and edits supplies (purchases are registered as expenses, in Gestión > Gastos).
class SuppliesPage extends ConsumerWidget {
  const SuppliesPage({super.key, this.canManage = false});

  /// Owner: create/edit/deactivate. Also means the page was pushed (back arrow, no logout).
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplies = ref.watch(suppliesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insumos'),
        actions: [const ConnectionIndicator(), if (!canManage) const LogoutButton()],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showSupplyDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo insumo'),
            )
          : null,
      body: switch (supplies) {
        AsyncValue(value: final list?) when list.isEmpty => EmptyView(
          icon: Icons.inventory_2_outlined,
          message: canManage ? 'Agrega los insumos que compras.' : 'El dueño aún no registró insumos.',
        ),
        AsyncValue(value: final list?) => RefreshIndicator(
          onRefresh: () => ref.read(suppliesProvider.notifier).refresh(),
          child: _SupplyList(supplies: list, canManage: canManage),
        ),
        AsyncError(:final error) => ErrorRetryView(
          error: error,
          onRetry: () => ref.invalidate(suppliesProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SupplyList extends ConsumerWidget {
  const _SupplyList({required this.supplies, required this.canManage});

  final List<Supply> supplies;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final low = supplies.where((s) => s.isActive && s.isLow).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (low.isNotEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(Icons.shopping_cart, color: theme.colorScheme.onErrorContainer),
              title: Text(
                'Por comprar (${low.length})',
                style: TextStyle(color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                low.map((s) => s.name).join(', '),
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        for (final supply in supplies)
          ListTile(
            leading: Icon(
              supply.isLow && supply.isActive ? Icons.warning_amber : Icons.inventory_2_outlined,
              color: supply.isLow && supply.isActive ? theme.colorScheme.error : null,
            ),
            title: Row(
              children: [
                Flexible(child: Text(supply.name, overflow: TextOverflow.ellipsis)),
                if (!supply.isActive) const InactiveTag('desactivado'),
              ],
            ),
            subtitle: Text(
              supply.minStock.isPositive ? 'Mínimo: ${supply.amount(supply.minStock)}' : 'Sin mínimo',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  supply.amount(supply.stock),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: supply.isLow && supply.isActive ? theme.colorScheme.error : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (supply.isLow && supply.isActive)
                  Text('Stock bajo', style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
              ],
            ),
            onTap: () => _showActions(context, ref, supply),
          ),
      ],
    );
  }

  void _showActions(BuildContext context, WidgetRef ref, Supply supply) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        void run(void Function() action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(supply.name, style: Theme.of(sheetContext).textTheme.titleMedium),
                subtitle: Text('Stock: ${supply.amount(supply.stock)}'),
              ),
              if (supply.isActive) ...[
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Registrar conteo'),
                  subtitle: const Text('Lo que hay realmente ahora'),
                  onTap: () => run(() => showMovementDialog(context, ref, supply, MovementType.count)),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Registrar merma'),
                  subtitle: const Text('Se malogró, se cayó, se venció'),
                  onTap: () => run(() => showMovementDialog(context, ref, supply, MovementType.waste)),
                ),
                ListTile(
                  leading: const Icon(Icons.outdoor_grill_outlined),
                  title: const Text('Registrar uso'),
                  subtitle: const Text('Lo que salió para cocinar'),
                  onTap: () => run(() => showMovementDialog(context, ref, supply, MovementType.use)),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Ver historial'),
                onTap: () => run(
                  () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => SupplyHistoryPage(supplyId: supply.id))),
                ),
              ),
              if (canManage) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar nombre o mínimo'),
                  onTap: () => run(() => showSupplyDialog(context, ref, supply)),
                ),
                ListTile(
                  leading: Icon(supply.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  title: Text(supply.isActive ? 'Desactivar (ya no se compra)' : 'Activar'),
                  onTap: () => run(() async {
                    await runSaving(context, () async {
                      final updated = await ref
                          .read(inventoryRepositoryProvider)
                          .updateSupply(supply.id, isActive: !supply.isActive);
                      ref.read(suppliesProvider.notifier).upsert(updated);
                    });
                  }),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Validates a typed quantity for [unit]: decimals only for kilos and litres.
String? validateQuantity(String? value, SupplyUnit unit, {bool allowZero = false, Quantity? max}) {
  final quantity = Quantity.tryParse(value);
  if (quantity == null || quantity.isNegative) return 'Cantidad no válida';
  if (!allowZero && !quantity.isPositive) return 'Debe ser mayor que 0';
  if (!unit.allowsDecimals && quantity.milli % 1000 != 0) return 'Solo números enteros';
  if (quantity.milli > 999999000) return 'Demasiado grande';
  if (max != null && quantity > max) return 'Solo hay ${max.toString()} ${unit.short}';
  return null;
}

Future<void> showMovementDialog(BuildContext context, WidgetRef ref, Supply supply, MovementType type) async {
  // One key per dialog: pressing Guardar again after a network error never subtracts twice
  final requestId = newRequestId();
  final (title, label, noteHint) = switch (type) {
    MovementType.count => ('Conteo de ${supply.name}', '¿Cuánto hay ahora?', 'Opcional'),
    MovementType.waste => ('Merma de ${supply.name}', '¿Cuánto se perdió?', 'Ej.: se malogró'),
    _ => ('Uso de ${supply.name}', '¿Cuánto salió?', 'Opcional'),
  };
  await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: const [null, null],
      builder: (dialogContext, controllers) {
        final [quantity, note] = controllers;
        return FormDialog(
          title: title,
          onSave: () => runSaving(dialogContext, () async {
            final updated = await ref
                .read(inventoryRepositoryProvider)
                .addMovement(
                  supply.id,
                  type: type,
                  quantity: Quantity.parse(quantity.text),
                  note: note.text,
                  requestId: requestId,
                );
            ref.read(suppliesProvider.notifier).upsert(updated);
            if (context.mounted) {
              showInfoSnack(context, '${updated.name}: quedan ${updated.amount(updated.stock)}');
            }
          }),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Según el sistema hay ${supply.amount(supply.stock)}.'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: quantity,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label, suffixText: supply.unit.short),
              validator: (value) => validateQuantity(
                value,
                supply.unit,
                allowZero: type == MovementType.count,
                max: type == MovementType.count ? null : supply.stock,
              ),
            ),
            TextFormField(
              controller: note,
              decoration: InputDecoration(labelText: 'Nota', hintText: noteHint),
              maxLength: 150,
            ),
          ],
        );
      },
    ),
  );
}

/// Create (no [supply]) or edit name and minimum. The unit is fixed once created: changing it
/// would silently reinterpret the stock (5 kg would become 5 units).
Future<void> showSupplyDialog(BuildContext context, WidgetRef ref, [Supply? supply]) async {
  var unit = supply?.unit ?? SupplyUnit.kg;
  await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: [
        supply?.name,
        supply == null || !supply.minStock.isPositive ? null : '${supply.minStock}',
      ],
      builder: (dialogContext, controllers) {
        final [name, minStock] = controllers;
        return StatefulBuilder(
          builder: (context, setState) => FormDialog(
            title: supply == null ? 'Nuevo insumo' : 'Editar ${supply.name}',
            onSave: () => runSaving(dialogContext, () async {
              final repository = ref.read(inventoryRepositoryProvider);
              final min = minStock.text.trim().isEmpty ? Quantity.zero : Quantity.parse(minStock.text);
              final saved = supply == null
                  ? await repository.createSupply(name: name.text, unit: unit, minStock: min)
                  : await repository.updateSupply(supply.id, name: name.text, minStock: min);
              ref.read(suppliesProvider.notifier).upsert(saved);
            }),
            children: [
              TextFormField(
                controller: name,
                autofocus: supply == null,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej.: Pescado, Limón, Aceite',
                ),
                validator: (value) => requiredText(value, max: 60),
              ),
              if (supply == null)
                DropdownButtonFormField<SupplyUnit>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Se mide en'),
                  items: [
                    for (final u in SupplyUnit.values) DropdownMenuItem(value: u, child: Text(u.label)),
                  ],
                  onChanged: (value) => setState(() => unit = value ?? unit),
                ),
              TextFormField(
                controller: minStock,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Avisar cuando quede (mínimo)',
                  hintText: 'Vacío = sin aviso',
                  suffixText: unit.short,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? null
                    : validateQuantity(value, unit, allowZero: true),
              ),
            ],
          ),
        );
      },
    ),
  );
}
