import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../models/admin.dart';
import '../../models/menu.dart';
import '../../state/admin.dart';
import '../../state/menu.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/text_controllers.dart';
import 'admin_widgets.dart';

/// Categories and dishes, including removed ones (to bring them back). Changes reach the
/// waiters instantly through `dish.updated`.
class MenuAdminPage extends ConsumerWidget {
  const MenuAdminPage({super.key});

  void _reload(WidgetRef ref) {
    ref.invalidate(adminCategoriesProvider);
    ref.invalidate(adminDishesProvider);
    ref.invalidate(menuProvider); // category changes do not emit realtime events
  }

  Future<void> _resetAvailability(BuildContext context, WidgetRef ref) async {
    if (!await confirm(
      context,
      title: 'Habilitar todos los platos',
      message: 'Los platos agotados vuelven a estar disponibles. Úsalo al inicio del día.',
      action: 'Habilitar',
    )) {
      return;
    }
    if (!context.mounted) return;
    await runSaving(context, () async {
      final count = await ref.read(menuRepositoryProvider).resetAvailability();
      _reload(ref);
      if (context.mounted) {
        showInfoSnack(context, count == 0 ? 'No había platos agotados' : '$count platos habilitados');
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(adminCategoriesProvider);
    final dishes = ref.watch(adminDishesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú'),
        actions: [
          IconButton(
            onPressed: () => _resetAvailability(context, ref),
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Habilitar todos los agotados',
          ),
          IconButton(
            onPressed: () async {
              if (await showCategoryDialog(context, ref) && context.mounted) _reload(ref);
            },
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Nueva categoría',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final active = (categories.value ?? const <Category>[]).where((c) => c.isActive).toList();
          if (active.isEmpty) {
            showInfoSnack(context, 'Primero crea una categoría (por ejemplo: Fondos, Bebidas).');
            return;
          }
          if (await showDishDialog(context, ref, categories: active) && context.mounted) _reload(ref);
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo plato'),
      ),
      body: switch ((categories, dishes)) {
        (AsyncValue(value: final cats?), AsyncValue(value: final list?)) => _MenuList(
          categories: cats,
          dishes: list,
          onChanged: () => _reload(ref),
        ),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => ErrorRetryView(error: error, onRetry: () => _reload(ref)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _MenuList extends ConsumerWidget {
  const _MenuList({required this.categories, required this.dishes, required this.onChanged});

  final List<Category> categories;
  final List<Dish> dishes;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categories.isEmpty) {
      return const EmptyView(icon: Icons.menu_book, message: 'Crea una categoría para empezar');
    }
    final activeCategories = categories.where((c) => c.isActive).toList();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final category in categories) ...[
          ListTile(
            tileColor: theme.colorScheme.surfaceContainerHighest,
            title: Row(
              children: [
                Flexible(
                  child: Text(category.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (!category.isActive) const InactiveTag('oculta'),
              ],
            ),
            subtitle: Text('Orden ${category.sortOrder}'),
            trailing: PopupMenuButton<String>(
              tooltip: 'Opciones de ${category.name}',
              onSelected: (action) async {
                if (action == 'edit') {
                  if (await showCategoryDialog(context, ref, category: category)) onChanged();
                  return;
                }
                if (category.isActive &&
                    !await confirm(
                      context,
                      title: 'Ocultar ${category.name}',
                      message: 'Sus platos dejarán de aparecer para los mozos. Puedes volver a mostrarla.',
                      action: 'Ocultar',
                    )) {
                  return;
                }
                if (!context.mounted) return;
                final saved = await runSaving(
                  context,
                  () => ref
                      .read(adminRepositoryProvider)
                      .updateCategory(category.id, isActive: !category.isActive),
                );
                if (saved) onChanged();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(category.isActive ? 'Ocultar' : 'Mostrar de nuevo'),
                ),
              ],
            ),
          ),
          for (final dish in dishes.where((d) => d.category.id == category.id))
            ListTile(
              enabled: dish.isActive,
              onTap: () async {
                if (await showDishDialog(context, ref, categories: activeCategories, dish: dish)) onChanged();
              },
              title: Row(
                children: [
                  Flexible(child: Text(dish.name)),
                  if (!dish.isActive) const InactiveTag('retirado'),
                ],
              ),
              subtitle: Text(
                [dish.price.toString(), if (dish.description != null) dish.description!].join(' · '),
              ),
              trailing: dish.isActive
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dish.isAvailable ? 'Disponible' : 'Agotado',
                          style: TextStyle(
                            fontSize: 12,
                            color: dish.isAvailable ? null : theme.colorScheme.error,
                          ),
                        ),
                        Switch(
                          value: dish.isAvailable,
                          onChanged: (value) async {
                            if (await runSaving(
                              context,
                              () => ref.read(menuRepositoryProvider).setAvailability(dish.id, value),
                            )) {
                              onChanged();
                            }
                          },
                        ),
                      ],
                    )
                  : TextButton(
                      onPressed: () async {
                        if (await runSaving(
                          context,
                          () => ref.read(adminRepositoryProvider).updateDish(dish.id, isActive: true),
                          success: '${dish.name} vuelve al menú',
                        )) {
                          onChanged();
                        }
                      },
                      child: const Text('Reactivar'),
                    ),
            ),
        ],
      ],
    );
  }
}

Future<bool> showCategoryDialog(BuildContext context, WidgetRef ref, {Category? category}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: [category?.name, '${category?.sortOrder ?? 0}'],
      builder: (dialogContext, controllers) {
        final [name, order] = controllers;
        return FormDialog(
          title: category == null ? 'Nueva categoría' : 'Editar categoría',
          onSave: () => runSaving(dialogContext, () async {
            final repository = ref.read(adminRepositoryProvider);
            final sortOrder = int.parse(order.text);
            if (category == null) {
              await repository.createCategory(name: name.text, sortOrder: sortOrder);
            } else {
              await repository.updateCategory(category.id, name: name.text, sortOrder: sortOrder);
            }
          }),
          children: [
            TextFormField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej.: Fondos, Entradas, Bebidas',
              ),
              validator: (value) => requiredText(value, max: 60),
            ),
            TextFormField(
              controller: order,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Orden en el menú',
                helperText: 'Menor número = aparece primero',
              ),
              validator: (value) {
                final number = int.tryParse(value ?? '');
                return number == null || number > 65535 ? 'Número entre 0 y 65535' : null;
              },
            ),
          ],
        );
      },
    ),
  );
  return saved ?? false;
}

Future<bool> showDishDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<Category> categories,
  Dish? dish,
}) async {
  // A dish whose category was hidden keeps it until the owner picks another one
  var categoryId = dish?.category.id ?? categories.first.id;
  final options = [
    ...categories,
    if (dish != null && !categories.any((c) => c.id == dish.category.id))
      Category(id: dish.category.id, name: '${dish.category.name} (oculta)', sortOrder: 0, isActive: false),
  ];

  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: [dish?.name, dish?.description, dish?.price.plain],
      builder: (_, controllers) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final [name, description, price] = controllers;
          return FormDialog(
            title: dish == null ? 'Nuevo plato' : 'Editar plato',
            onSave: () => runSaving(dialogContext, () async {
              final repository = ref.read(adminRepositoryProvider);
              final amount = Money.parse(price.text);
              if (dish == null) {
                await repository.createDish(
                  categoryId: categoryId,
                  name: name.text,
                  price: amount,
                  description: description.text,
                );
              } else {
                await repository.updateDish(
                  dish.id,
                  categoryId: categoryId == dish.category.id ? null : categoryId,
                  name: name.text,
                  price: amount,
                  description: description.text,
                );
              }
            }),
            children: [
              TextFormField(
                controller: name,
                autofocus: dish == null,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (value) => requiredText(value),
              ),
              TextFormField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,5}([.,]\d{0,2})?'))],
                decoration: const InputDecoration(labelText: 'Precio', prefixText: 'S/ '),
                validator: (value) => Money.tryParse(value) == null ? 'Precio inválido' : null,
              ),
              DropdownButtonFormField<int>(
                initialValue: categoryId,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [for (final c in options) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (value) => setState(() => categoryId = value ?? categoryId),
              ),
              TextFormField(
                controller: description,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
              ),
              if (dish != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
                    onPressed: () async {
                      final removed = await runSaving(
                        dialogContext,
                        () => ref.read(adminRepositoryProvider).updateDish(dish.id, isActive: false),
                        success: '${dish.name} retirado del menú',
                      );
                      if (removed && dialogContext.mounted) Navigator.pop(dialogContext, true);
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Retirar del menú'),
                  ),
                ),
                const Text(
                  'Los pedidos anteriores conservan el nombre y precio con que se vendieron.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
  return saved ?? false;
}
