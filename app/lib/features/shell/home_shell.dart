import '../online/online_orders_screen.dart';
import '../../app/theme.dart';
import '../cloud/notices.dart';
import '../kitchen/kitchen_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../profile/app_drawer.dart';
import '../tokens/tokens_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../cloud/access_controller.dart';
import '../bills/bills_screen.dart';
import '../cloud/cloud_reporter.dart';
import '../cloud/cloud_screens.dart';
import '../cloud/support_screen.dart';
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
  const _Dest(this.key, this.label, this.icon, this.permission, this.builder, {this.module});
  final String key;
  final String label;
  final IconData icon;
  final String permission;
  final Widget Function() builder;

  /// null = always on; otherwise shown only while this module is on.
  final String? module;
}

/// In priority order: the first four are always on the bottom bar of a phone; the rest live under "More".
final _destinations = <_Dest>[
  _Dest('pos', 'pos', Icons.point_of_sale, 'pos.sell', () => const PosScreen()),
  _Dest('dashboard', 'dashboard', Icons.dashboard_outlined, 'reports.view', () => const SizedBox.shrink()),
  _Dest('tables', 'tables', Icons.table_restaurant_outlined, 'pos.sell', () => const TablesScreen(), module: 'tables'),
  _Dest('kitchen', 'kitchen_board', Icons.soup_kitchen_outlined, 'pos.sell', () => const KitchenScreen(), module: 'kitchen'),
  _Dest('online', 'online', Icons.delivery_dining_outlined, 'pos.sell', () => const OnlineOrdersScreen(), module: 'online'),
  _Dest('tokens', 'tokens', Icons.confirmation_number_outlined, 'pos.sell', () => const TokensScreen(), module: 'tokens'),
  _Dest('bills', 'bills_title', Icons.receipt_long_outlined, 'pos.sell', () => const BillsScreen()),
  _Dest('reports', 'reports', Icons.bar_chart_rounded, 'reports.view', () => const ReportsScreen()),
  _Dest('customers', 'customers', Icons.people_alt_outlined, 'pos.sell', () => const CustomersScreen(), module: 'customers'),
  _Dest('expenses', 'expenses', Icons.payments_outlined, 'pos.sell', () => const ExpensesScreen(), module: 'expenses'),
  _Dest('inventory', 'inventory', Icons.inventory_2_outlined, 'inventory.manage', () => const InventoryScreen(), module: 'inventory'),
  _Dest('menu', 'menu', Icons.restaurant_menu, 'menu.manage', () => const MenuScreen()),
  _Dest('staff', 'staff', Icons.badge_outlined, 'staff.manage', () => const StaffScreen(), module: 'staff'),
  _Dest('settings', 'settings', Icons.settings_outlined, 'settings.manage', () => const SettingsScreen()),
];

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final session = ref.watch(sessionProvider)!;
    final modules = ref.watch(activeModulesProvider);
    // the Tokens screen only appears once the owner has set up at least one token type
    final hasTokens = ref.watch(tokenConfigProvider).value?.active.isNotEmpty ?? false;
    final dests = _destinations.where((d) => session.canOpen(d.key, d.permission) && (d.module == null || modules.contains(d.module)) && (d.key != 'tokens' || hasTokens)).toList();
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
    final actions = [
      const CloudSyncIndicator(),
      const NoticeBell(),
      if (ref.watch(cloudGatewayProvider) != null)
        IconButton(key: const ValueKey('support'), tooltip: t['support'], icon: const Icon(Icons.support_agent), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupportScreen()))),
      IconButton(key: const ValueKey('sign-out'), tooltip: t['sign_out'], icon: const Icon(Icons.logout), onPressed: () => ref.read(sessionProvider.notifier).signOut())
    ];
    final body = Column(children: [const AccessBanner(), const KitchenReadyWatcher(), if (session.can('settings.manage')) const LocationAsk(), const NoticePusher(), const NoticePermissionAsk(), Expanded(child: KeyedSubtree(key: ValueKey(current.key), child: current.key == 'dashboard' ? DashboardScreen(onGo: go) : current.builder()))]);

    if (wide) {
      return Scaffold(
        appBar: DtAppBar(title: title, actions: actions),
        drawer: AppDrawer(onGo: go),
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
      appBar: DtAppBar(title: title, actions: actions),
      drawer: AppDrawer(onGo: go),
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
                for (final d in onBar) NavigationDestination(icon: d.key == 'kitchen' ? Badge(isLabelVisible: ref.watch(kitchenReadyCountProvider) > 0, label: Text('${ref.watch(kitchenReadyCountProvider)}'), child: Icon(d.icon)) : Icon(d.icon), label: d.label == 'online' ? t['online_short'] : t[d.label]),
                if (needMore) NavigationDestination(key: const ValueKey('nav-more'), icon: const Icon(Icons.apps_rounded), label: t['more']),
              ],
            ),
    );
  }
}
