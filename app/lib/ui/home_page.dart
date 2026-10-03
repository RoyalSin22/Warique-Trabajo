import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../state/session.dart';
import 'inventory/supplies_page.dart';
import 'kitchen/dish_availability_page.dart';
import 'kitchen/kitchen_board_page.dart';
import 'owner/admin_page.dart';
import 'owner/report_page.dart';
import 'waiter/waiter_orders_page.dart';

/// Picks the screens by role. The backend enforces permissions; this only shapes the UI.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProvider).role;
    final tabs = switch (role) {
      Role.waiter => const [_Tab('Pedidos', Icons.receipt_long, WaiterOrdersPage())],
      Role.kitchen => const [
        _Tab('Cocina', Icons.soup_kitchen, KitchenBoardPage()),
        _Tab('Platos', Icons.no_meals, DishAvailabilityPage()),
        _Tab('Insumos', Icons.inventory_2, SuppliesPage()),
      ],
      // Sold-out switches for the owner live in Gestión > Menú
      Role.owner => const [
        _Tab('Pedidos', Icons.receipt_long, WaiterOrdersPage()),
        _Tab('Cocina', Icons.soup_kitchen, KitchenBoardPage()),
        _Tab('Cierre', Icons.point_of_sale, ReportPage()),
        _Tab('Gestión', Icons.settings, AdminPage()),
      ],
    };
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(index: index, children: [for (final tab in tabs) tab.page]),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: [
                for (final tab in tabs) NavigationDestination(icon: Icon(tab.icon), label: tab.label),
              ],
            ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.page);

  final String label;
  final IconData icon;
  final Widget page;
}
