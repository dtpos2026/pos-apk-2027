import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../cloud/access_controller.dart';
import '../../data/receipt_loader.dart' show formatDateTime;
import '../../data/receipt_settings.dart';
import '../common/dialogs.dart';

/// The restaurant's own profile: name, owner, contact, address, tax numbers and logo. Saved on the phone and used on every receipt.
class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});
  @override
  ConsumerState<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxLabel = TextEditingController();
  final _taxNo = TextEditingController();
  String? _logoPath;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final c in [_name, _owner, _phone, _address, _taxLabel, _taxNo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final b = await ref.read(businessProvider.future);
    final logo = await ref.read(logoStoreProvider).path();
    if (!mounted) return;
    setState(() {
      _name.text = b?.name ?? '';
      _owner.text = b?.ownerName ?? '';
      _phone.text = b?.phone ?? '';
      _address.text = b?.address ?? '';
      _taxLabel.text = b?.taxLabel ?? 'NTN';
      _taxNo.text = b?.taxNumber ?? '';
      _logoPath = logo;
      _loaded = true;
    });
  }

  Future<void> _pickLogo() async {
    final t = Strings.of(context);
    final bytes = await ref.read(logoPickerProvider).pick();
    if (bytes == null) return;
    try {
      await ref.read(logoStoreProvider).save(bytes);
      final p = await ref.read(logoStoreProvider).path();
      if (mounted) setState(() => _logoPath = p);
      ref.invalidate(businessProvider);
    } catch (_) {
      if (mounted) showMessage(context, t['logo_error']);
    }
  }

  Future<void> _save() async {
    final t = Strings.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = t['required']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await updateBusinessProfile(ref.read(databaseProvider),
        name: _name.text, ownerName: _owner.text, phone: _phone.text, address: _address.text, taxLabel: _taxLabel.text, taxNumber: _taxNo.text, now: ref.read(clockProvider)().millisecondsSinceEpoch);
    ref.invalidate(businessProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(context, t['saved']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t['business_profile'])),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Center(
                child: GestureDetector(
                  key: const ValueKey('profile-logo'),
                  onTap: _pickLogo,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: cs.primary.withValues(alpha: 0.1),
                    backgroundImage: _logoPath == null ? null : FileImage(File(_logoPath!)),
                    child: _logoPath == null ? Icon(Icons.add_a_photo_outlined, size: 32, color: cs.primary) : null,
                  ),
                ),
              ),
              Center(child: TextButton(onPressed: _pickLogo, child: Text(t['choose_logo']))),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('profile-name'), controller: _name, decoration: InputDecoration(labelText: t['business_name'], errorText: _error)),
              const SizedBox(height: 12),
              TextField(key: const ValueKey('profile-owner'), controller: _owner, decoration: InputDecoration(labelText: t['owner_name'])),
              const SizedBox(height: 12),
              TextField(key: const ValueKey('profile-phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t['phone'])),
              const SizedBox(height: 12),
              TextField(key: const ValueKey('profile-address'), controller: _address, minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: t['address'])),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(width: 130, child: TextField(controller: _taxLabel, decoration: InputDecoration(labelText: t['tax_label']))),
                const SizedBox(width: 10),
                Expanded(child: TextField(key: const ValueKey('profile-tax'), controller: _taxNo, decoration: InputDecoration(labelText: t['tax_number']))),
              ]),
              const SizedBox(height: 8),
              Text(t['profile_hint'], style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 18),
              FilledButton(key: const ValueKey('profile-save'), onPressed: _busy ? null : _save, child: Text(t['save'])),
            ]),
    );
  }
}

/// Subscription and account details from Digital Target (kept on the phone from the last time it was online).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final access = ref.watch(accessProvider);
    final biz = ref.watch(businessProvider).value;
    final cs = Theme.of(context).colorScheme;
    final a = access is AccessDecided ? access.account : null;
    final email = access is AccessDecided ? access.user.email : null;
    Widget row(String k, String v, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(child: Text(v, key: key, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    final statusColor = switch (a?.status) { 'active' => Colors.green.shade700, 'pending' || 'payment_pending' => Colors.orange.shade800, null => cs.outline, _ => Colors.red.shade700 };
    return Scaffold(
      appBar: AppBar(title: Text(t['account_licence'])),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(biz?.name ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (a != null)
                  Container(
                    key: const ValueKey('account-status'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: statusColor)),
                    child: Text(t['acc_status_${a.status}'], style: TextStyle(color: statusColor, fontWeight: FontWeight.w800)),
                  ),
              ]),
              const Divider(height: 24),
              if (a == null) Text(t['account_local_only']) else ...[
                if (email != null) row(t['signed_in_as'], email),
                if (a.customerId != null) row(t['customer_id'], a.customerId!, key: const ValueKey('account-customer-id')),
                if (a.plan != null) row(t['plan'], a.plan!),
                row(t['expires_on'], a.expiresAt == null ? t['no_expiry'] : formatDateTime(a.expiresAt!).substring(0, 10), key: const ValueKey('account-expiry')),
                row(t['approved_phones'], '${a.approvedPhones.length}'),
                if (a.adminMessage.isNotEmpty) row(t['message_from_dt'], a.adminMessage),
                row(t['last_checked'], formatDateTime(a.checkedAt)),
              ],
              row(t['app_version'], ref.watch(appVersionProvider)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(t['account_offline_note'], style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
