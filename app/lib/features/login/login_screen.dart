import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../common/person_avatar.dart';
import '../../app/whatsapp.dart';
import '../../cloud/access_controller.dart';
import '../../app/strings.dart';
import '../../data/auth_service.dart';
import '../../data/queries.dart';
import 'brand_footer.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  StaffEntry? _who;
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final t = Strings.of(context);
    setState(() => _busy = true);
    final r = await ref.read(sessionProvider.notifier).signIn(_who!.id, _pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      if (r == PinResult.ok) ref.read(pinResetNoticeProvider.notifier).clear();
      _error = switch (r) { PinResult.ok => null, PinResult.locked => t['pin_locked'], _ => t['wrong_pin'] };
    });
  }

  void _press(String d) {
    if (_busy || _pin.length >= 8) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final staff = ref.watch(staffListProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const SizedBox(height: 8),
                _BusinessHeader(compact: _who != null),
                const SizedBox(height: 6),
                if (ref.watch(pinResetNoticeProvider))
                  Container(
                    key: const ValueKey('pin-reset-banner'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF1B7F3B), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.lock_reset, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t['pin_reset_done'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                Text(_who == null ? t['choose_user'] : _who!.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 20),
                Expanded(
                  child: _who == null
                      ? staff.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('$e'),
                          data: (list) => ListView(children: [
                            for (final s in list)
                              Card(
                                child: ListTile(
                                  key: ValueKey('staff-${s.name}'),
                                  leading: PersonAvatar(name: s.name, imagePath: s.imagePath),
                                  title: Text(s.name),
                                  subtitle: Text(s.roleName),
                                  onTap: () => setState(() => _who = s),
                                ),
                              ),
                          ]),
                        )
                      : _PinPad(pin: _pin, error: _error, title: t['enter_pin'], onDigit: _press, onBack: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)), onSubmit: _pin.length >= 4 ? _submit : null, onChangeUser: () => setState(() {
                            _who = null;
                            _pin = '';
                            _error = null;
                          })),
                ),
                TextButton(key: const ValueKey('forgot-pin'), onPressed: () => showDialog<void>(context: context, builder: (_) => const _ForgotPinDialog()), child: Text(t['forgot_pin'])),
                const BrandFooter(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.pin, required this.error, required this.title, required this.onDigit, required this.onBack, required this.onSubmit, required this.onChangeUser});
  final String pin;
  final String? error;
  final String title;
  final void Function(String) onDigit;
  final VoidCallback onBack;
  final VoidCallback? onSubmit;
  final VoidCallback onChangeUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: 62,
            child: FilledButton.tonal(key: ValueKey('key-$label'), onPressed: onTap, child: child ?? Text(label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
          ),
        );
    return Column(children: [
      Text(title),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < (pin.length < 4 ? 4 : pin.length); i++)
          Container(margin: const EdgeInsets.all(6), width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: i < pin.length ? scheme.primary : scheme.outlineVariant)),
      ]),
      SizedBox(height: 22, child: Text(error ?? '', key: const ValueKey('pin-error'), style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600))),
      Expanded(
        child: GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 1.45,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) key(d, onTap: () => onDigit(d)),
            key('back', onTap: onBack, child: const Icon(Icons.backspace_outlined)),
            key('0', onTap: () => onDigit('0')),
            key('ok', onTap: onSubmit, child: const Icon(Icons.check_rounded)),
          ],
        ),
      ),
      TextButton(onPressed: onChangeUser, child: const Icon(Icons.swap_horiz)),
    ]);
  }
}

/// Business logo, name, address and phone, all centred: the face of the app on the sign-in screen.
class _BusinessHeader extends ConsumerWidget {
  const _BusinessHeader({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(businessProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final logo = b?.logoPath;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5);
    return Column(children: [
      if (logo != null && File(logo).existsSync())
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Image.file(File(logo), key: const ValueKey('login-logo'), height: compact ? 56 : 96, fit: BoxFit.contain)),
      Text(b?.name ?? Strings.of(context)['app_name'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
      if (!compact && (b?.address?.trim().isNotEmpty ?? false)) Padding(padding: const EdgeInsets.only(top: 2), child: Text(b!.address!, textAlign: TextAlign.center, style: muted)),
      if (!compact && (b?.phone?.trim().isNotEmpty ?? false)) Padding(padding: const EdgeInsets.only(top: 2), child: Text(b!.phone!, textAlign: TextAlign.center, style: muted)),
    ]);
  }
}

/// Tells the owner how to get a new PIN. Closes itself the moment the panel's reset reaches this phone.
class _ForgotPinDialog extends ConsumerStatefulWidget {
  const _ForgotPinDialog();
  @override
  ConsumerState<_ForgotPinDialog> createState() => _ForgotPinDialogState();
}

class _ForgotPinDialogState extends ConsumerState<_ForgotPinDialog> {
  String _whatsapp = '';

  @override
  void initState() {
    super.initState();
    ref.read(cloudGatewayProvider)?.branding().then((b) {
      if (mounted && b != null) setState(() => _whatsapp = b.whatsapp.trim());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    ref.listen(pinResetNoticeProvider, (_, on) {
      if (on && mounted) Navigator.of(context).pop();
    });
    return AlertDialog(
      title: Text(t['forgot_pin_title']),
      content: Text(t['forgot_pin_body'], key: const ValueKey('forgot-pin-body')),
      actions: [
        if (_whatsapp.isNotEmpty)
          TextButton.icon(
            key: const ValueKey('forgot-pin-whatsapp'),
            onPressed: () => sendViaWhatsApp(ref, _whatsapp, '${ref.read(businessProvider).value?.name ?? ''}: ${t['forgot_pin_title']}'.trim()),
            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
            label: Text(t['support_whatsapp']),
          ),
        TextButton(key: const ValueKey('forgot-pin-close'), onPressed: () => Navigator.of(context).pop(), child: Text(t['close'])),
      ],
    );
  }
}
