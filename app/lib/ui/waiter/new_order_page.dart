import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/money.dart';
import '../../models/menu.dart';
import '../../models/order.dart';
import '../../state/menu.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import 'cart.dart';

/// Builds a new order. Pops with the created [Order].
class NewOrderPage extends ConsumerStatefulWidget {
  const NewOrderPage({super.key});

  @override
  ConsumerState<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends ConsumerState<NewOrderPage> {
  final _cart = Cart();
  OrderType _type = OrderType.dineIn;
  int? _tableId;
  final _customerController = TextEditingController();
  final _notesController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _customerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _add(Dish dish) {
    if (!_cart.add(dish.id)) {
      showInfoSnack(context, 'Límite alcanzado: 99 unidades por plato y 50 platos distintos.');
    }
    setState(() {});
  }

  Future<void> _editNote(Dish dish) async {
    final controller = TextEditingController(text: _cart.noteOf(dish.id));
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nota: ${dish.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 150,
          decoration: const InputDecoration(hintText: 'Ej.: sin ají, bien cocido'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    controller.dispose();
    if (note != null) setState(() => _cart.setNote(dish.id, note));
  }

  String? _validationError(Map<int, Dish> menu) {
    if (_cart.isEmpty) return 'Agrega al menos un plato';
    if (_type == OrderType.dineIn && _tableId == null) return 'Selecciona una mesa';
    if (_cart.unavailable(menu).isNotEmpty) return 'Hay platos agotados en el pedido';
    return null;
  }

  Future<void> _submit(Map<int, Dish> menu) async {
    final error = _validationError(menu);
    if (error != null) {
      showInfoSnack(context, error);
      return;
    }
    setState(() => _submitting = true);
    try {
      final order = await ref.read(ordersRepositoryProvider).create(
            orderType: _type,
            tableId: _tableId,
            customerName: _type == OrderType.takeaway ? _customerController.text : null,
            notes: _notesController.text,
            items: _cart.toItems(),
          );
      if (mounted) Navigator.of(context).pop(order);
    } on ApiException catch (error) {
      if (!mounted) return;
      // Someone marked a dish as sold out after it was added: drop it and tell the waiter
      if (error.unavailableDishIds.isNotEmpty) {
        setState(() => error.unavailableDishIds.forEach(_cart.removeDish));
        ref.read(menuProvider.notifier).refresh();
      }
      showErrorSnack(context, error);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _review(Map<int, Dish> menu) async {
    final error = _validationError(menu);
    if (error != null) {
      showInfoSnack(context, error);
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ReviewSheet(
        cart: _cart,
        menu: menu,
        target: _type == OrderType.dineIn
            ? (ref.read(tablesProvider).value ?? const <DiningTable>[])
                .firstWhere((t) => t.id == _tableId, orElse: () => const DiningTable(id: 0, label: 'Mesa'))
                .label
            : 'Para llevar',
        notesController: _notesController,
      ),
    );
    if (confirmed == true && mounted) await _submit(menu);
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo pedido'), actions: const [ConnectionIndicator()]),
      body: Column(children: [
        _TargetSelector(
          type: _type,
          tableId: _tableId,
          customerController: _customerController,
          onTypeChanged: (type) => setState(() => _type = type),
          onTableChanged: (id) => setState(() => _tableId = id),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (menuAsync) {
            AsyncValue(value: final dishes?) => _MenuTabs(
                dishes: dishes,
                cart: _cart,
                onAdd: _add,
                onRemove: (dish) => setState(() => _cart.remove(dish.id)),
                onNote: _editNote,
              ),
            AsyncError(:final error) =>
              ErrorRetryView(error: error, onRetry: () => ref.invalidate(menuProvider)),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ]),
      bottomNavigationBar: switch (menuAsync.value) {
        final dishes? => _CartBar(
            cart: _cart,
            menu: {for (final dish in dishes) dish.id: dish},
            submitting: _submitting,
            onReview: _review,
          ),
        null => null,
      },
    );
  }
}

class _TargetSelector extends ConsumerWidget {
  const _TargetSelector({
    required this.type,
    required this.tableId,
    required this.customerController,
    required this.onTypeChanged,
    required this.onTableChanged,
  });

  final OrderType type;
  final int? tableId;
  final TextEditingController customerController;
  final ValueChanged<OrderType> onTypeChanged;
  final ValueChanged<int?> onTableChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<OrderType>(
          segments: const [
            ButtonSegment(value: OrderType.dineIn, label: Text('Mesa'), icon: Icon(Icons.table_restaurant)),
            ButtonSegment(value: OrderType.takeaway, label: Text('Para llevar'), icon: Icon(Icons.takeout_dining)),
          ],
          selected: {type},
          onSelectionChanged: (selection) => onTypeChanged(selection.first),
        ),
        const SizedBox(height: 8),
        if (type == OrderType.dineIn)
          switch (tables) {
            AsyncValue(value: final list?) when list.isEmpty =>
              const Text('No hay mesas registradas. El dueño debe crearlas.'),
            AsyncValue(value: final list?) => SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final table in list)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(table.label),
                        selected: table.id == tableId,
                        onSelected: (selected) => onTableChanged(selected ? table.id : null),
                      ),
                    ),
                ]),
              ),
            AsyncError() => TextButton.icon(
                onPressed: () => ref.invalidate(tablesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('No se pudieron cargar las mesas. Reintentar'),
              ),
            _ => const LinearProgressIndicator(),
          }
        else
          TextField(
            controller: customerController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Nombre del cliente (opcional)',
              isDense: true,
              counterText: '',
            ),
          ),
      ]),
    );
  }
}

class _MenuTabs extends StatelessWidget {
  const _MenuTabs({
    required this.dishes,
    required this.cart,
    required this.onAdd,
    required this.onRemove,
    required this.onNote,
  });

  final List<Dish> dishes;
  final Cart cart;
  final ValueChanged<Dish> onAdd;
  final ValueChanged<Dish> onRemove;
  final ValueChanged<Dish> onNote;

  @override
  Widget build(BuildContext context) {
    if (dishes.isEmpty) {
      return const EmptyView(icon: Icons.menu_book, message: 'El menú está vacío');
    }
    // Server already orders by category sortOrder, then name
    final categories = <int, (CategoryRef, List<Dish>)>{};
    for (final dish in dishes) {
      categories.putIfAbsent(dish.category.id, () => (dish.category, <Dish>[])).$2.add(dish);
    }
    final groups = categories.values.toList();

    return DefaultTabController(
      length: groups.length,
      child: Column(children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final (category, list) in groups)
              Tab(text: _badge(category.name, list.fold(0, (sum, d) => sum + cart.quantityOf(d.id)))),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            for (final (_, list) in groups)
              ListView.separated(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _DishRow(
                  dish: list[index],
                  quantity: cart.quantityOf(list[index].id),
                  note: cart.noteOf(list[index].id),
                  onAdd: onAdd,
                  onRemove: onRemove,
                  onNote: onNote,
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  static String _badge(String name, int count) => count == 0 ? name : '$name ($count)';
}

class _DishRow extends StatelessWidget {
  const _DishRow({
    required this.dish,
    required this.quantity,
    required this.note,
    required this.onAdd,
    required this.onRemove,
    required this.onNote,
  });

  final Dish dish;
  final int quantity;
  final String? note;
  final ValueChanged<Dish> onAdd;
  final ValueChanged<Dish> onRemove;
  final ValueChanged<Dish> onNote;

  @override
  Widget build(BuildContext context) {
    final soldOut = !dish.isAvailable;
    final theme = Theme.of(context);
    return ListTile(
      enabled: !soldOut || quantity > 0,
      onTap: soldOut ? null : () => onAdd(dish),
      title: Text(
        dish.name,
        style: soldOut ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
      ),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(soldOut ? '${dish.price} · AGOTADO' : dish.price.toString(),
            style: soldOut ? TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold) : null),
        if (note != null)
          Text('Nota: $note', style: TextStyle(color: Colors.amber.shade900, fontStyle: FontStyle.italic)),
      ]),
      trailing: quantity == 0
          ? IconButton.filledTonal(
              onPressed: soldOut ? null : () => onAdd(dish),
              icon: const Icon(Icons.add),
              tooltip: 'Agregar',
            )
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                onPressed: () => onNote(dish),
                icon: Icon(note == null ? Icons.edit_note : Icons.sticky_note_2),
                tooltip: 'Nota para cocina',
              ),
              IconButton(onPressed: () => onRemove(dish), icon: const Icon(Icons.remove_circle_outline)),
              Text('$quantity', style: theme.textTheme.titleMedium),
              IconButton(
                onPressed: soldOut ? null : () => onAdd(dish),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart, required this.menu, required this.submitting, required this.onReview});

  final Cart cart;
  final Map<int, Dish> menu;
  final bool submitting;
  final void Function(Map<int, Dish>) onReview;

  @override
  Widget build(BuildContext context) {
    final soldOut = cart.unavailable(menu);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (soldOut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Agotado: ${soldOut.map((id) => menu[id]?.name ?? 'plato retirado').join(', ')}. Quítalo para continuar.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${cart.unitCount} ${cart.unitCount == 1 ? 'plato' : 'platos'}'),
                Text(cart.total(menu).toString(), style: Theme.of(context).textTheme.titleLarge),
              ]),
            ),
            FilledButton.icon(
              onPressed: cart.isEmpty || submitting ? null : () => onReview(menu),
              icon: submitting
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('Revisar y enviar'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({
    required this.cart,
    required this.menu,
    required this.target,
    required this.notesController,
  });

  final Cart cart;
  final Map<int, Dish> menu;
  final String target;
  final TextEditingController notesController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(target, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
          child: ListView(shrinkWrap: true, children: [
            for (final id in cart.dishIds)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text('${cart.quantityOf(id)}×', style: Theme.of(context).textTheme.titleMedium),
                title: Text(menu[id]?.name ?? 'Plato #$id'),
                subtitle: cart.noteOf(id) == null ? null : Text(cart.noteOf(id)!),
                trailing: Text(((menu[id]?.price ?? Money.zero) * cart.quantityOf(id)).toString()),
              ),
          ]),
        ),
        TextField(
          controller: notesController,
          maxLength: 255,
          decoration: const InputDecoration(labelText: 'Nota general del pedido (opcional)'),
        ),
        Row(children: [
          Expanded(child: Text('Total estimado', style: Theme.of(context).textTheme.titleMedium)),
          Text(cart.total(menu).toString(), style: Theme.of(context).textTheme.titleLarge),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.soup_kitchen),
          label: const Text('Enviar a cocina'),
        ),
      ]),
    );
  }
}
