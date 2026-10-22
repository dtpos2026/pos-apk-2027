import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../menu/menu_screen.dart';
import '../pos/pos_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';

class _Dest {
  const _Dest(this.key, this.icon, this.permission, this.builder);
  final String key;
  final IconData icon;
  final String permission;
  final Widget Function() builder;
}

final _destinations = <_Dest>[
  _Dest('pos', Icons.point_of_sale, 'pos.sell', () => const PosScreen()),
  _Dest('menu', Icons.restaurant_menu, 'menu.manage', () => const MenuScreen()),
  _Dest('reports', Icons.bar_chart_rounded, 'reports.view', () => const ReportsScreen()),
  _Dest('settings', Icons.settings_outlined, 'settings.manage', () => const SettingsScreen()),
];

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final session = ref.watch(sessionProvider)!;
    final dests = _destinations.where((d) => session.can(d.permission)).toList();
    final index = _index.clamp(0, dests.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = dests[index].builder();

    final title = Row(children: [
      Text(t['app_name'], style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(width: 12),
      Flexible(child: Text(session.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
    ]);
    final actions = [IconButton(tooltip: t['sign_out'], icon: const Icon(Icons.logout), onPressed: () => ref.read(sessionProvider.notifier).signOut())];

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: title, actions: actions),
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(t[d.key]))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      body: body,
      bottomNavigationBar: dests.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.icon), label: t[d.key])],
            ),
    );
  }
}
