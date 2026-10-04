import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin.dart';
import '../../state/admin.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/text_controllers.dart';
import 'admin_widgets.dart';

class TablesAdminPage extends ConsumerWidget {
  const TablesAdminPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [ManagedTable? table]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => WithTextControllers(
        initialTexts: [table?.label],
        builder: (dialogContext, controllers) {
          final label = controllers.single;
          return FormDialog(
            title: table == null ? 'Nueva mesa' : 'Renombrar mesa',
            onSave: () => runSaving(dialogContext, () async {
              final repository = ref.read(adminRepositoryProvider);
              if (table == null) {
                await repository.createTable(label.text);
              } else {
                await repository.updateTable(table.id, label: label.text);
              }
            }),
            children: [
              TextFormField(
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej.: Mesa 4, Terraza 1'),
                validator: (value) => requiredText(value, max: 20),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) ref.invalidate(adminTablesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(adminTablesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mesas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva mesa'),
      ),
      body: switch (tables) {
        AsyncValue(value: final list?) when list.isEmpty => const EmptyView(
          icon: Icons.table_restaurant,
          message: 'Sin mesas. Solo se podrá vender para llevar.',
        ),
        AsyncValue(value: final list?) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final table in list)
              ListTile(
                leading: const Icon(Icons.table_restaurant),
                title: Row(
                  children: [Text(table.label), if (!table.isActive) const InactiveTag('desactivada')],
                ),
                onTap: () => _edit(context, ref, table),
                trailing: Switch(
                  value: table.isActive,
                  onChanged: (value) async {
                    if (await runSaving(
                      context,
                      () => ref.read(adminRepositoryProvider).updateTable(table.id, isActive: value),
                    )) {
                      ref.invalidate(adminTablesProvider);
                    }
                  },
                ),
              ),
          ],
        ),
        AsyncError(:final error) => ErrorRetryView(
          error: error,
          onRetry: () => ref.invalidate(adminTablesProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
