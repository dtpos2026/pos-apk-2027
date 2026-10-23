import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../bills/bills_screen.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../inventory/inventory_screen.dart';
import '../menu/menu_screen.dart';
import '../pos/pos_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../staff/staff_screen.dart';
import '../tables/tables_screen.dart';

class _Dest {
  const _Dest(this.key, this.label, this.icon, this.permission, this.builder);
  final String key;
  final String label;
  final IconData icon;
  final String permission;
  final Widget Function() builder;
}

/// In priority order: the first four are always on the bottom bar of a phone; the rest live under "More".
final _destinations = <_Dest>[
  _Dest('pos', 'pos', Icons.point_of_sale, 'pos.sell', () => const PosScreen()),
  _Dest('tables', 'tables', Icons.table_restaurant_outlined, 'pos.sell', () => const TablesScreen()),
  _Dest('bills', 'bills_title', Icons.receipt_long_outlined, 'pos.sell', () => const BillsScreen()),
  _Dest('reports', 'reports', Icons.bar_chart_rounded, 'reports.view', () => const ReportsScreen()),
  _Dest('customers', 'customers', Icons.people_alt_outlined, 'pos.sell', () => const CustomersScreen()),
  _Dest('expenses', 'expenses', Icons.payments_outlined, 'pos.sell', () => const ExpensesScreen()),
  _Dest('inventory', 'inventory', Icons.inventory_2_outlined, 'inventory.manage', () => const InventoryScreen()),
  _Dest('menu', 'menu', Icons.restaurant_menu, 'menu.manage', () => const MenuScreen()),
  _Dest('staff', 'staff', Icons.badge_outlined, 'staff.manage', () => const StaffScreen()),
  _Dest('settings', 'settings', Icons.settings_outlined, 'settings.manage', () => const SettingsScreen()),
];

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final session = ref.watch(sessionProvider)!;
    final dests = _destinations.where((d) => session.can(d.permission)).toList();
    final tab = ref.watch(shellTabProvider);
    final current = dests.firstWhere((d) => d.key == tab, orElse: () => dests.first);
    final index = dests.indexOf(current);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    void go(String key) => ref.read(shellTabProvider.notifier).go(key);

    final title = Row(children: [
      Text(t['app_name'], style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(width: 12),
      Flexible(child: Text(session.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
    ]);
    final actions = [IconButton(key: const ValueKey('sign-out'), tooltip: t['sign_out'], icon: const Icon(Icons.logout), onPressed: () => ref.read(sessionProvider.notifier).signOut())];
    final body = KeyedSubtree(key: ValueKey(current.key), child: current.builder());

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: title, actions: actions),
        body: Row(children: [
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: index,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (i) => go(dests[i].key),
                    destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(t[d.label]))],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }

    // phone: up to 4 destinations on the bar, and "More" for the rest
    final needMore = dests.length > 5;
    final onBar = needMore ? dests.take(4).toList() : dests;
    final overflow = needMore ? dests.skip(4).toList() : const <_Dest>[];
    final inOverflow = overflow.contains(current);
    final barIndex = inOverflow ? onBar.length : onBar.indexOf(current).clamp(0, onBar.length - 1);

    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      body: body,
      bottomNavigationBar: dests.length < 2
          ? null
          : NavigationBar(
              selectedIndex: barIndex,
              onDestinationSelected: (i) async {
                if (i < onBar.length) {
                  go(onBar[i].key);
                  return;
                }
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: Wrap(children: [
                      for (final d in overflow) SizedBox(width: MediaQuery.sizeOf(ctx).width / 3, child: InkWell(key: ValueKey('more-${d.key}'), onTap: () => Navigator.pop(ctx, d.key), child: Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Column(children: [Icon(d.icon, size: 28), const SizedBox(height: 6), Text(t[d.label], textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5))])))),
                    ]),
                  ),
                );
                if (picked != null) go(picked);
              },
              destinations: [
                for (final d in onBar) NavigationDestination(icon: Icon(d.icon), label: t[d.label]),
                if (needMore) NavigationDestination(key: const ValueKey('nav-more'), icon: const Icon(Icons.apps_rounded), label: t['more']),
              ],
            ),
    );
  }
}
