import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/pos_service.dart';
import '../../data/staff_service.dart';
import '../common/dialogs.dart';

final _staffProvider = FutureProvider.autoDispose<List<StaffRow>>((ref) => ref.watch(staffServiceProvider).list());

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

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
                    }
                    ref.invalidate(_staffProvider);
                  }),
                  itemBuilder: (_) => [PopupMenuItem(value: 'toggle', child: Text(r.active ? s['deactivate'] : s['activate'])), PopupMenuItem(value: 'pin', child: Text(s['reset_pin']))],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
