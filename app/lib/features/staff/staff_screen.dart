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
import '../common/dialogs.dart';

final _staffProvider = FutureProvider.autoDispose<List<StaffRow>>((ref) => ref.watch(staffServiceProvider).list());

/// Staff list and attendance (clock in / out, hours and wages per month).
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(key: const ValueKey('tab-staff'), text: s['staff']), Tab(key: const ValueKey('tab-attendance'), text: s['attendance'])]),
        const Expanded(child: TabBarView(children: [_StaffList(), AttendanceTab()])),
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
    final v = await showFormDialog(
      context,
      title: s['add_staff'],
      fields: [FieldSpec('name', s['name']), FieldSpec('pin', s['pin'], number: true, obscure: true), FieldSpec('phone', s['phone'], required: false)],
      extra: (set) => DropdownButtonFormField<String>(key: const ValueKey('staff-role'), initialValue: role, decoration: InputDecoration(labelText: s['role']), items: [for (final r in roles) DropdownMenuItem(value: r.id, child: Text(r.name))], onChanged: (x) => set(() => role = x ?? role)),
      validate: (v) async {
        try {
          await ref.read(staffServiceProvider).add(actor: ref.read(sessionProvider)!.staffId, name: v['name']!, roleId: role, pin: v['pin']!, phone: v['phone']);
          return null;
        } on PosException catch (e) {
          return e.message;
        } on ArgumentError {
          return s['pin_invalid'];
        }
      },
    );
    if (v != null) ref.invalidate(_staffProvider);
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
                    } else if (a == 'wage') {
                      final cur = await svc.dailyWage(r.id);
                      if (!context.mounted) return;
                      final v = await showFormDialog(context, title: '${s['daily_wage']}: ${r.name}', fields: [FieldSpec('wage', s['amount'], number: true, initial: cur == 0 ? '' : formatMinor(cur, currency: ref.currency, symbol: false).replaceAll(',', ''))]);
                      if (v != null) await svc.setDailyWage(actor: me, staffId: r.id, wageMinor: parseMinor(v['wage']!, currency: ref.currency) ?? 0);
                    }
                    ref.invalidate(_staffProvider);
                  }),
                  itemBuilder: (_) => [PopupMenuItem(value: 'toggle', child: Text(r.active ? s['deactivate'] : s['activate'])), PopupMenuItem(value: 'pin', child: Text(s['reset_pin'])), PopupMenuItem(value: 'wage', child: Text(s['daily_wage']))],
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
