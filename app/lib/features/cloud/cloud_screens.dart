import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../cloud/access_controller.dart';
import '../../cloud/cloud_gateway.dart';
import '../../cloud/location_consent.dart';
import '../../domain/account_gate.dart';
import '../login/brand_footer.dart';
import 'support_screen.dart';

/// Digital Target branded layout for the account screens: red header (same as the splash), content on a card.
Widget _frame(BuildContext context, {required List<Widget> children}) {
  final top = MediaQuery.paddingOf(context).top;
  return Scaffold(
    body: SingleChildScrollView(
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(24, top + 40, 24, 84),
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC92A2A), Color(0xFF6E0F0F)]),
          ),
          child: Column(children: [
            Image.asset('assets/brand/dt_mark_white.png', height: 52),
            const SizedBox(height: 12),
            Text(Strings.of(context)['app_name'], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            const Text('Digital Target', style: TextStyle(color: Color(0xFFF7CFCF), fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.6)),
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(bottom: 24), child: BrandFooter()),
      ]),
    ),
  );
}

/// Firebase could not start (wrong or missing configuration).
class SetupIncompleteScreen extends StatelessWidget {
  const SetupIncompleteScreen({super.key, required this.problem});
  final String problem;
  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return _frame(context, children: [
      Text(t['setup_incomplete_title'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(t['setup_incomplete_body']),
      const SizedBox(height: 8),
      Text(problem, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]);
  }
}

class CheckingScreen extends StatelessWidget {
  const CheckingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Sign in or create an account (email + password).
class CloudAuthScreen extends ConsumerStatefulWidget {
  const CloudAuthScreen({super.key});
  @override
  ConsumerState<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends ConsumerState<CloudAuthScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _create = false;
  bool _busy = false;
  String? _error;
  String? _info;
  Branding? _branding;

  @override
  void initState() {
    super.initState();
    ref.read(cloudGatewayProvider)?.branding().then((b) {
      if (mounted) setState(() => _branding = b);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final t = Strings.of(context);
    if (!_email.text.contains('@') || _pw.text.length < 6) {
      setState(() => _error = t['auth_check_fields']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final gw = ref.read(cloudGatewayProvider)!;
    try {
      _create ? await gw.signUp(_email.text, _pw.text) : await gw.signIn(_email.text, _pw.text);
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final t = Strings.of(context);
    if (!_email.text.contains('@')) {
      setState(() => _error = t['auth_type_email']);
      return;
    }
    try {
      await ref.read(cloudGatewayProvider)!.resetPassword(_email.text);
      if (mounted) setState(() { _info = t['reset_sent']; _error = null; });
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final b = _branding;
    return _frame(context, children: [
      Text(_create ? t['create_account'] : t['sign_in'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      TextField(key: const Key('cloud_email'), controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: t['email'], prefixIcon: const Icon(Icons.mail_outline))),
      const SizedBox(height: 12),
      TextField(key: const Key('cloud_password'), controller: _pw, obscureText: true, decoration: InputDecoration(labelText: t['password'], prefixIcon: const Icon(Icons.lock_outline))),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, key: const Key('cloud_error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (_info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_info!)),
      const SizedBox(height: 16),
      FilledButton(key: const Key('cloud_submit'), onPressed: _busy ? null : _go, child: Text(_create ? t['create_account'] : t['sign_in'])),
      TextButton(onPressed: _busy ? null : () => setState(() { _create = !_create; _error = null; }), child: Text(_create ? t['have_account'] : t['no_account'])),
      if (!_create) TextButton(onPressed: _busy ? null : _reset, child: Text(t['forgot_password'])),
      if (b != null && (b.contact.isNotEmpty || b.supportMessage.isNotEmpty)) ...[
        const Divider(),
        if (b.supportMessage.isNotEmpty) Text(b.supportMessage, textAlign: TextAlign.center),
        if (b.contact.isNotEmpty) Text(b.contact, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ]);
  }
}

/// First-time registration of the restaurant; Digital Target approves it from the panel.
class RegisterBusinessScreen extends ConsumerStatefulWidget {
  const RegisterBusinessScreen({super.key, required this.user});
  final CloudUser user;
  @override
  ConsumerState<RegisterBusinessScreen> createState() => _RegisterBusinessScreenState();
}

class _RegisterBusinessScreenState extends ConsumerState<RegisterBusinessScreen> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  String _country = 'PK';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _owner, _phone, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final t = Strings.of(context);
    if ([_name, _owner, _phone].any((c) => c.text.trim().isEmpty)) {
      setState(() => _error = t['fill_required']);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(accessProvider.notifier).submitRegistration(RegistrationData(
          businessName: _name.text.trim(), ownerName: _owner.text.trim(), phone: _phone.text.trim(), city: _city.text.trim(), country: _country, email: widget.user.email));
    } on CloudException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return _frame(context, children: [
      Text(t['register_title'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(widget.user.email, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      TextField(key: const Key('reg_name'), controller: _name, decoration: InputDecoration(labelText: t['business_name'], prefixIcon: const Icon(Icons.storefront_outlined))),
      const SizedBox(height: 12),
      TextField(key: const Key('reg_owner'), controller: _owner, decoration: InputDecoration(labelText: t['owner_name'], prefixIcon: const Icon(Icons.person_outline))),
      const SizedBox(height: 12),
      TextField(key: const Key('reg_phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t['phone'], prefixIcon: const Icon(Icons.phone_outlined))),
      const SizedBox(height: 12),
      TextField(key: const Key('reg_city'), controller: _city, decoration: InputDecoration(labelText: t['city'], prefixIcon: const Icon(Icons.location_city_outlined))),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _country,
        decoration: InputDecoration(labelText: t['country']),
        items: [DropdownMenuItem(value: 'PK', child: Text(t['pakistan'])), DropdownMenuItem(value: 'AE', child: Text(t['uae']))],
        onChanged: (v) => setState(() => _country = v ?? 'PK'),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, key: const Key('reg_error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      FilledButton(key: const Key('reg_submit'), onPressed: _busy ? null : _submit, child: Text(t['submit_approval'])),
      TextButton(onPressed: () => ref.read(accessProvider.notifier).signOut(), child: Text(t['sign_out'])),
    ]);
  }
}

/// Shown for every reason the app may not sell right now. Data on the phone is never touched.
class AccessBlockedScreen extends ConsumerWidget {
  const AccessBlockedScreen({super.key, required this.state});
  final AccessDecided state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final d = state.decision;
    final (key, icon) = switch (d.reason) {
      AccessReason.waitingApproval => ('waiting', Icons.hourglass_top),
      AccessReason.rejected => ('rejected', Icons.cancel_outlined),
      AccessReason.suspended => ('suspended', Icons.pause_circle_outline),
      AccessReason.blocked => ('blocked', Icons.block),
      AccessReason.paymentPending => ('payment', Icons.payments_outlined),
      AccessReason.expired => ('expired', Icons.event_busy),
      AccessReason.phoneBlocked => ('phone_blocked', Icons.phonelink_erase),
      AccessReason.newPhone => ('new_phone', Icons.phone_android),
      AccessReason.internetNeeded => ('internet', Icons.wifi_off),
      AccessReason.clockTampered => ('clock', Icons.schedule),
      AccessReason.updateRequired => ('update', Icons.system_update),
      AccessReason.ok => ('waiting', Icons.check),
    };
    return _frame(context, children: [
      Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12),
      Text(t['blk_${key}_t'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(t['blk_${key}_b'], textAlign: TextAlign.center),
      if (d.message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(d.message, key: const Key('admin_message'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
      if (d.reason != AccessReason.updateRequired) ...[
        const SizedBox(height: 8),
        Text(t['data_safe'], textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
      const SizedBox(height: 20),
      FilledButton(key: const Key('check_again'), onPressed: () => ref.read(accessProvider.notifier).refresh(), child: Text(t['check_again'])),
      OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupportScreen())), child: Text(t['contact_support'])),
      TextButton(onPressed: () => ref.read(accessProvider.notifier).signOut(), child: Text(t['sign_out'])),
    ]);
  }
}

/// Subscription reminder (7 days or less) and the notice Digital Target wrote for every restaurant.
class AccessBanner extends ConsumerWidget {
  const AccessBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accessProvider);
    if (state is! AccessDecided) return const SizedBox.shrink();
    final t = Strings.of(context);
    final lines = <String>[
      if (state.decision.daysLeft != null && state.decision.daysLeft! <= 7) t['expiry_soon'].replaceAll('{n}', '${state.decision.daysLeft}'),
      if (state.control.notice.isNotEmpty) state.control.notice,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('access_banner'),
      width: double.infinity,
      color: Theme.of(context).colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(lines.join('\n'), style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer)),
    );
  }
}

/// Asks the owner once, after sign-in, whether Digital Target may see this phone's location. Renders nothing.
class LocationAsk extends ConsumerStatefulWidget {
  const LocationAsk({super.key});
  @override
  ConsumerState<LocationAsk> createState() => _LocationAskState();
}

class _LocationAskState extends ConsumerState<LocationAsk> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(locationConsentProvider);
    final access = ref.watch(accessProvider);
    if (!_asked && ref.watch(locationSourceProvider) != null && access is AccessDecided && access.decision.allowed && consent.hasValue && consent.value == null) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final t = Strings.of(context);
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.location_on_outlined),
            title: Text(t['location_ask_title']),
            content: Text(t['location_ask_body']),
            actions: [
              TextButton(key: const Key('location-no'), onPressed: () => Navigator.pop(c, false), child: Text(t['not_now'])),
              FilledButton(key: const Key('location-yes'), onPressed: () => Navigator.pop(c, true), child: Text(t['allow'])),
            ],
          ),
        );
        await ref.read(locationConsentProvider.notifier).set(yes == true);
      });
    }
    return const SizedBox.shrink();
  }
}
