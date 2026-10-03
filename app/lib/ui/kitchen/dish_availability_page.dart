import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/menu.dart';
import '../../state/menu.dart';
import '../widgets/common.dart';

/// "Agotado" switch per dish. Waiters see the change instantly (dish.updated).
class DishAvailabilityPage extends ConsumerStatefulWidget {
  const DishAvailabilityPage({super.key});

  @override
  ConsumerState<DishAvailabilityPage> createState() => _DishAvailabilityPageState();
}

class _DishAvailabilityPageState extends ConsumerState<DishAvailabilityPage> {
  final _busy = <int>{};
  String _query = '';

  Future<void> _toggle(Dish dish, bool isAvailable) async {
    setState(() => _busy.add(dish.id));
    try {
      await ref.read(menuProvider.notifier).setAvailability(dish, isAvailable);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(dish.id));
    }
  }

  Future<void> _resetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Habilitar todos los platos'),
        content: const Text('Todos los platos agotados vuelven a estar disponibles. '
            'Úsalo al inicio del día.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Habilitar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await ref.read(menuProvider.notifier).resetAvailability();
      if (mounted) showInfoSnack(context, count == 0 ? 'No había platos agotados' : '$count platos habilitados');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platos disponibles'),
        actions: [
          const ConnectionIndicator(),
          IconButton(onPressed: _resetAll, icon: const Icon(Icons.restart_alt), tooltip: 'Habilitar todos'),
          const LogoutButton(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar plato',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      body: switch (menu) {
        AsyncValue(value: final dishes?) => _buildList(dishes),
        AsyncError(:final error) => ErrorRetryView(error: error, onRetry: () => ref.invalidate(menuProvider)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildList(List<Dish> dishes) {
    final filtered = _query.isEmpty ? dishes : dishes.where((d) => d.name.toLowerCase().contains(_query)).toList();
    final soldOut = dishes.where((d) => !d.isAvailable).length;
    if (filtered.isEmpty) return const EmptyView(icon: Icons.search_off, message: 'Sin resultados');

    return ListView.builder(
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(soldOut == 0 ? 'Todo disponible' : '$soldOut agotado(s)',
                style: Theme.of(context).textTheme.titleSmall),
          );
        }
        final dish = filtered[index - 1];
        final showHeader = index == 1 || filtered[index - 2].category.id != dish.category.id;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(dish.category.name,
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
          SwitchListTile(
            title: Text(dish.name),
            subtitle: Text(dish.isAvailable ? 'Disponible' : 'AGOTADO',
                style: dish.isAvailable ? null : TextStyle(color: Theme.of(context).colorScheme.error)),
            value: dish.isAvailable,
            onChanged: _busy.contains(dish.id) ? null : (value) => _toggle(dish, value),
          ),
        ]);
      },
    );
  }
}
