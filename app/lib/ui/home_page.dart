import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../state/inventory.dart';
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
    final tabCount = role == Role.waiter ? 1 : (role == Role.kitchen ? 3 : 4);
    final index = _index.clamp(0, tabCount - 1);
    // The board stays mounted in the IndexedStack: it must know when it is on screen (screen-on
    // lock, and for the owner also sounds and dialogs, only while visible)
    final tabs = switch (role) {
      Role.waiter => const [_Tab('Pedidos', Icons.receipt_long, WaiterOrdersPage())],
      Role.kitchen => [
        _Tab('Cocina', Icons.soup_kitchen, KitchenBoardPage(visible: index == 0)),
        const _Tab('Platos', Icons.no_meals, DishAvailabilityPage()),
        const _Tab('Insumos', Icons.inventory_2, SuppliesPage(), showsLowStock: true),
      ],
      // Sold-out switches for the owner live in Gestión > Menú
      Role.owner => [
        const _Tab('Pedidos', Icons.receipt_long, WaiterOrdersPage()),
        _Tab('Cocina', Icons.soup_kitchen, KitchenBoardPage(visible: index == 1)),
        const _Tab('Cierre', Icons.point_of_sale, ReportPage()),
        const _Tab('Gestión', Icons.settings, AdminPage(), showsLowStock: true),
      ],
    };
    // Waiters never see supplies: their account cannot read them
    final lowStock = role == Role.waiter ? 0 : ref.watch(lowSupplyCountProvider);

    return Scaffold(
      body: IndexedStack(index: index, children: [for (final tab in tabs) tab.page]),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: tab.showsLowStock && lowStock > 0,
                      label: Text('$lowStock'),
                      child: Icon(tab.icon),
                    ),
                    label: tab.label,
                    tooltip: tab.showsLowStock && lowStock > 0
                        ? '${tab.label}: $lowStock con stock bajo'
                        : null,
                  ),
              ],
            ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.page, {this.showsLowStock = false});

  final String label;
  final IconData icon;
  final Widget page;

  /// Badge with the number of supplies at or under their minimum.
  final bool showsLowStock;
}
