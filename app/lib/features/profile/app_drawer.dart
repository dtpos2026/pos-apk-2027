import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../cloud/access_controller.dart';
import '../cloud/support_screen.dart';
import '../settings/receipt_design_screen.dart';
import '../tokens/tokens_settings_screen.dart';
import 'profile_screens.dart';

/// The menu behind the three lines in the corner: the restaurant's profile and account, shortcuts, sign out.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.onGo});

  /// Switches the main screen (e.g. 'settings').
  final void Function(String key) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final session = ref.watch(sessionProvider)!;
    final biz = ref.watch(businessProvider).value;
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(accessProvider);
    final status = access is AccessDecided ? access.account?.status : null;
    void open(Widget screen) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    }

    final header = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 20),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.45)!])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: Colors.white,
          backgroundImage: biz?.logoPath == null || !File(biz!.logoPath!).existsSync() ? null : FileImage(File(biz.logoPath!)),
          child: biz?.logoPath == null || !File(biz!.logoPath!).existsSync() ? Icon(Icons.storefront_outlined, size: 34, color: cs.primary) : null,
        ),
        const SizedBox(height: 12),
        Text(biz?.name ?? t['app_name'], key: const ValueKey('drawer-name'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        if ((biz?.ownerName ?? '').isNotEmpty) Text(biz!.ownerName!, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Row(children: [
          Flexible(child: Text(session.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          if (status != null) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)), child: Text(t['acc_status_$status'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
          ],
        ]),
      ]),
    );

    return Drawer(
      child: Column(children: [
        header,
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            if (session.can('settings.manage')) ListTile(key: const ValueKey('drawer-profile'), leading: const Icon(Icons.badge_outlined), title: Text(t['business_profile']), onTap: () => open(const BusinessProfileScreen())),
            ListTile(key: const ValueKey('drawer-account'), leading: const Icon(Icons.verified_user_outlined), title: Text(t['account_licence']), onTap: () => open(const AccountScreen())),
            const Divider(),
            if (session.can('settings.manage')) ListTile(key: const ValueKey('drawer-receipt'), leading: const Icon(Icons.receipt_long_outlined), title: Text(t['receipt_design']), onTap: () => open(const ReceiptDesignScreen())),
            if (session.can('settings.manage') && ref.watch(activeModulesProvider).contains('tokens'))
              ListTile(key: const ValueKey('drawer-tokens'), leading: const Icon(Icons.confirmation_number_outlined), title: Text(t['tokens_title']), onTap: () => open(const TokensSettingsScreen())),
            if (session.can('settings.manage'))
              ListTile(key: const ValueKey('drawer-settings'), leading: const Icon(Icons.settings_outlined), title: Text(t['settings']), onTap: () {
                Navigator.of(context).pop();
                onGo('settings');
              }),
            if (ref.watch(cloudGatewayProvider) != null) ListTile(key: const ValueKey('drawer-support'), leading: const Icon(Icons.support_agent), title: Text(t['support']), onTap: () => open(const SupportScreen())),
          ]),
        ),
        const Divider(height: 1),
        ListTile(key: const ValueKey('drawer-sign-out'), leading: const Icon(Icons.logout), title: Text(t['sign_out']), onTap: () {
          Navigator.of(context).pop();
          ref.read(sessionProvider.notifier).signOut();
        }),
        Padding(padding: EdgeInsets.only(bottom: 10 + MediaQuery.paddingOf(context).bottom), child: Text('${t['powered_by']}  ·  v${ref.watch(appVersionProvider)}', style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
