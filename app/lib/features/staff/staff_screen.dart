import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/attendance_service.dart';
import '../../data/pos_service.dart';
import '../../domain/money.dart';
import '../../app/format.dart';
import '../../data/receipt_loader.dart' show two;
import '../../data/staff_service.dart';
import '../../data/team_service.dart';
import '../common/dialogs.dart';

final _staffProvider = FutureProvider.autoDispose<List<StaffRow>>((ref) => ref.watch(staffServiceProvider).list());

/// Staff list and attendance (clock in / out, hours and wages per month).
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(tabs: [Tab(key: const ValueKey('tab-staff'), text: s['staff']), Tab(key: const ValueKey('tab-riders'), text: s['riders']), Tab(key: const ValueKey('tab-attendance'), text: s['attendance'])]),
        const Expanded(child: TabBarView(children: [_StaffList(), RidersTab(), AttendanceTab()])),
      ]),
    );
  }
}

class _StaffList extends ConsumerWidget {
  const _StaffList();

  Future<void> _guard(BuildContext context, Future<void> Function() fn) async {
    try {
      await fn();
    } on PosException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    } on ArgumentError catch (e) {
      if (context.mounted) showMessage(context, '${e.message}');
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final s = Strings.of(context);
    final roles = await ref.read(staffServiceProvider).roles();
    if (!context.mounted) return;
    var role = roles.firstWhere((r) => r.name == 'Cashier', orElse: () => roles.first).id;
    var custom = false;
    String? newId;
    final v = await showFormDialog(
      context,
      title: s['add_staff'],
      fields: [FieldSpec('name', s['name']), FieldSpec('pin', s['pin'], number: true, obscure: true), FieldSpec('phone', s['phone'], required: false)],
      extra: (set) => Column(children: [DropdownButtonFormField<String>(key: const ValueKey('staff-role'), initialValue: role, decoration: InputDecoration(labelText: s['role']), items: [for (final r in roles) DropdownMenuItem(value: r.id, child: Text(r.name))], onChanged: (x) => set(() => role = x ?? role)),
        SwitchListTile(key: const ValueKey('staff-custom'), contentPadding: EdgeInsets.zero, dense: true, title: Text(s['access_choose']), value: custom, onChanged: (v) => set(() => custom = v)),
      ]),
      validate: (v) async {
        try {
          newId = await ref.read(staffServiceProvider).add(actor: ref.read(sessionProvider)!.staffId, name: v['name']!, roleId: role, pin: v['pin']!, phone: v['phone']);
          return null;
        } on PosException catch (e) {
          return e.message;
        } on ArgumentError {
          return s['pin_invalid'];
        }
      },
    );
    if (v != null) {
      ref.invalidate(_staffProvider);
      if (custom && newId != null && context.mounted) await _editAccess(context, ref, newId!, v['name']!);
    }
  }

  /// The screens and actions one person may use. Starts from what their role gives today.
  Future<void> _editAccess(BuildContext context, WidgetRef ref, String staffId, String name) async {
    final svc = ref.read(staffServiceProvider);
    final cur = await svc.accessOf(staffId);
    if (!context.mounted) return;
    final r = await showDialog<({Set<String> screens, Set<String> actions})>(context: context, builder: (_) => _AccessDialog(name: name, screens: cur.screens, actions: cur.actions));
    if (r == null || !context.mounted) return;
    await _guard(context, () => svc.setAccess(actor: ref.read(sessionProvider)!.staffId, staffId: staffId, screens: r.screens, actions: r.actions));
    ref.invalidate(_staffProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final me = ref.watch(sessionProvider)!.staffId;
    final list = ref.watch(_staffProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-staff'), onPressed: () => _add(context, ref), icon: const Icon(Icons.person_add_alt_1), label: Text(s['add_staff'])),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            return Card(
              child: ListTile(
                key: ValueKey('staff-row-${r.name}'),
                leading: CircleAvatar(child: Text(r.name.characters.first.toUpperCase())),
                title: Text(r.name, style: TextStyle(fontWeight: FontWeight.w600, decoration: r.active ? null : TextDecoration.lineThrough)),
                subtitle: Text('${r.roleName}${r.active ? '' : '  ·  ${s['inactive']}'}'),
                trailing: PopupMenuButton<String>(
                  key: ValueKey('staff-menu-${r.name}'),
                  onSelected: (a) => _guard(context, () async {
                    final svc = ref.read(staffServiceProvider);
                    if (a == 'toggle') {
                      await svc.setActive(actor: me, staffId: r.id, active: !r.active);
                    } else if (a == 'pin') {
                      final v = await showFormDialog(context, title: s['reset_pin'], fields: [FieldSpec('pin', s['pin'], number: true, obscure: true)]);
                      if (v != null) await svc.resetPin(actor: me, staffId: r.id, newPin: v['pin']!);
                    } else if (a == 'access') {
                      await _editAccess(context, ref, r.id, r.name);
                    } else if (a == 'wage') {
                      final cur = await svc.dailyWage(r.id);
                      if (!context.mounted) return;
                      final v = await showFormDialog(context, title: '${s['daily_wage']}: ${r.name}', fields: [FieldSpec('wage', s['amount'], number: true, initial: cur == 0 ? '' : formatMinor(cur, currency: ref.currency, symbol: false).replaceAll(',', ''))]);
                      if (v != null) await svc.setDailyWage(actor: me, staffId: r.id, wageMinor: parseMinor(v['wage']!, currency: ref.currency) ?? 0);
                    }
                    ref.invalidate(_staffProvider);
                  }),
                  itemBuilder: (_) => [PopupMenuItem(key: ValueKey('staff-access-${r.name}'), value: 'access', child: Text(s['access_title'])), PopupMenuItem(value: 'toggle', child: Text(r.active ? s['deactivate'] : s['activate'])), PopupMenuItem(value: 'pin', child: Text(s['reset_pin'])), PopupMenuItem(value: 'wage', child: Text(s['daily_wage']))],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

final _attDayProvider = FutureProvider.autoDispose.family<List<AttendanceRow>, String>((ref, day) => ref.watch(attendanceServiceProvider).forDay(day));
final _attMonthProvider = FutureProvider.autoDispose.family<List<AttendanceMonth>, String>((ref, ym) => ref.watch(attendanceServiceProvider).month(ym, now: ref.watch(clockProvider)()));

/// Today: who is at work, with In / Out buttons. Below: hours, days and wages for the month.
class AttendanceTab extends ConsumerWidget {
  const AttendanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final now = ref.watch(clockProvider)();
    final day = '${now.year}-${two(now.month)}-${two(now.day)}';
    final ym = day.substring(0, 7);
    final today = ref.watch(_attDayProvider(day)).value ?? const <AttendanceRow>[];
    final month = ref.watch(_attMonthProvider(ym)).value ?? const <AttendanceMonth>[];
    final svc = ref.read(attendanceServiceProvider);
    String time(int? ms) => ms == null ? '-' : () { final d = DateTime.fromMillisecondsSinceEpoch(ms); return '${two(d.hour)}:${two(d.minute)}'; }();
    Future<void> act(Future<void> Function() f) async {
      try {
        await f();
      } on PosException catch (e) {
        if (context.mounted) showMessage(context, e.message);
      }
      ref.invalidate(_attDayProvider);
      ref.invalidate(_attMonthProvider);
    }

    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      Text('${s['today']} · $day', style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final r in today)
        Card(
          child: ListTile(
            key: ValueKey('att-${r.staffName}'),
            title: Text(r.staffName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(r.checkIn == null ? s['not_in_yet'] : '${s['att_in']} ${time(r.checkIn)}   ${s['att_out']} ${time(r.checkOut)}   ${hoursText(r.minutes(now))}'),
            trailing: r.atWork
                ? FilledButton.tonal(key: ValueKey('clock-out-${r.staffName}'), onPressed: () => act(() => svc.clockOut(r.staffId)), child: Text(s['clock_out']))
                : FilledButton(key: ValueKey('clock-in-${r.staffName}'), onPressed: () => act(() => svc.clockIn(r.staffId)), child: Text(s['clock_in'])),
          ),
        ),
      const SizedBox(height: 14),
      Text('${s['this_month']} · $ym', style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      if (month.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(s['att_none'])),
      for (final m in month)
        Card(
          child: ListTile(
            key: ValueKey('att-month-${m.staffName}'),
            title: Text(m.staffName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${m.days} ${s['days']} · ${hoursText(m.minutes)}'),
            trailing: Text(ref.money(m.wageMinor), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
  }
}

/// Tick the screens this person can open and the things they may do. Staff and Settings are never offered: they stay with owner and manager.
class _AccessDialog extends StatefulWidget {
  const _AccessDialog({required this.name, required this.screens, required this.actions});
  final String name;
  final Set<String> screens;
  final Set<String> actions;
  @override
  State<_AccessDialog> createState() => _AccessDialogState();
}

class _AccessDialogState extends State<_AccessDialog> {
  late final Set<String> _screens = {...widget.screens};
  late final Set<String> _actions = {...widget.actions};

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    Widget box(String key, String label, Set<String> set, String value) => CheckboxListTile(
          key: ValueKey(key),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label),
          value: set.contains(value),
          onChanged: (v) => setState(() => v == true ? set.add(value) : set.remove(value)),
        );
    return AlertDialog(
      title: Text('${s['access_title']}: ${widget.name}'),
      scrollable: true,
      content: SizedBox(
        width: 340,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['access_screens'], style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final sc in accessScreens) box('acc-screen-$sc', s['acc_screen_$sc'], _screens, sc),
          const Divider(),
          Text(s['access_actions'], style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final a in accessActions) box('acc-act-$a', s['acc_act_$a'], _actions, a),
        ]),
      ),
      actions: [
        DialogActions([
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s['cancel'])),
          FilledButton(key: const ValueKey('access-save'), onPressed: _screens.isEmpty ? null : () => Navigator.pop(context, (screens: _screens, actions: _actions)), child: Text(s['save'])),
        ]),
      ],
    );
  }
}

final _ridersProvider = FutureProvider.autoDispose<List<RiderRow>>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(teamServiceProvider).riders(day: '${now.year}-${two(now.month)}-${two(now.day)}');
});

/// Delivery riders: add, edit, hide. Each card shows today's deliveries so the owner sees who did what.
class RidersTab extends ConsumerWidget {
  const RidersTab({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, RiderRow? r) async {
    final s = Strings.of(context);
    final v = await showFormDialog(
      context,
      title: r == null ? s['add_rider'] : r.name,
      fields: [
        FieldSpec('name', s['name'], initial: r?.name ?? ''),
        FieldSpec('phone', s['phone'], initial: r?.phone ?? '', required: false),
        FieldSpec('bike', s['rider_bike'], initial: r?.bikeNo ?? '', required: false),
      ],
      validate: (v) async {
        try {
          await ref.read(teamServiceProvider).saveRider(id: r?.id, name: v['name']!, phone: v['phone'], bikeNo: v['bike'], staffId: ref.read(sessionProvider)!.staffId);
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null) ref.invalidate(_ridersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final list = ref.watch(_ridersProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-rider'), onPressed: () => _edit(context, ref, null), icon: const Icon(Icons.two_wheeler_outlined), label: Text(s['add_rider'])),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => rows.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(s['riders_none'], textAlign: TextAlign.center)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return Card(
                    child: ListTile(
                      key: ValueKey('rider-${r.name}'),
                      leading: CircleAvatar(child: Icon(Icons.two_wheeler_outlined, color: r.active ? null : Theme.of(context).colorScheme.outline)),
                      title: Text(r.name, style: TextStyle(fontWeight: FontWeight.w600, decoration: r.active ? null : TextDecoration.lineThrough)),
                      subtitle: Text([if ((r.phone ?? '').isNotEmpty) r.phone!, if ((r.bikeNo ?? '').isNotEmpty) r.bikeNo!, '${r.deliveries} ${s['rider_today']}${r.deliveries > 0 ? ' · ${ref.money(r.totalMinor)}' : ''}'].join('  ·  ')),
                      onTap: () => _edit(context, ref, r),
                      trailing: PopupMenuButton<String>(
                        key: ValueKey('rider-menu-${r.name}'),
                        onSelected: (a) async {
                          final svc = ref.read(teamServiceProvider);
                          final me = ref.read(sessionProvider)!.staffId;
                          if (a == 'toggle') await svc.setActive(r.id, !r.active, staffId: me);
                          if (a == 'delete') await svc.delete(r.id, staffId: me);
                          ref.invalidate(_ridersProvider);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'toggle', child: Text(r.active ? s['deactivate'] : s['activate'])),
                          PopupMenuItem(key: ValueKey('rider-delete-${r.name}'), value: 'delete', child: Text(s['delete'])),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
