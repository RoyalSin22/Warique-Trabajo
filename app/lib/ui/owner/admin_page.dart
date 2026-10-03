import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/common.dart';
import 'menu_admin_page.dart';
import 'tables_admin_page.dart';
import 'users_admin_page.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión'), actions: const [ConnectionIndicator(), LogoutButton()]),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('Menú'),
            subtitle: const Text('Categorías, platos, precios y agotados'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const MenuAdminPage()),
          ),
          ListTile(
            leading: const Icon(Icons.table_restaurant),
            title: const Text('Mesas'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const TablesAdminPage()),
          ),
          ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Usuarios'),
            subtitle: const Text('Mozos, cocina y claves'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const UsersAdminPage()),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Cambiar mi contraseña'),
            onTap: () => showChangeOwnPasswordDialog(context, ref),
          ),
        ],
      ),
    );
  }
}
