import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/whatsapp.dart';
import '../help/help_screen.dart';
import '../../cloud/access_controller.dart';
import '../../cloud/cloud_gateway.dart';

/// Chat with Digital Target support.
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});
  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _text = TextEditingController();
  String? _error;
  String _whatsapp = '';

  @override
  void initState() {
    super.initState();
    // the support WhatsApp number comes from the Super Admin panel (Branding); without internet the button just stays hidden
    ref.read(cloudGatewayProvider)?.branding().then((b) {
      if (mounted && b != null) setState(() => _whatsapp = b.whatsapp.trim());
    }).catchError((_) {});
  }

  /// The restaurant's own name (what support should see), not the owner's.
  String get _restaurant {
    final local = ref.read(businessProvider).value?.name.trim() ?? '';
    if (local.isNotEmpty) return local;
    final state = ref.read(accessProvider);
    return state is AccessDecided ? (state.account?.businessName ?? '') : '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  CloudUser? get _user => ref.read(cloudGatewayProvider)?.currentUser;

  Future<void> _send() async {
    final msg = _text.text.trim();
    final user = _user;
    if (msg.isEmpty || user == null) return;
    try {
      await ref.read(cloudGatewayProvider)!.sendSupport(user.uid, _restaurant, msg);
      _text.clear();
      setState(() => _error = null);
    } on CloudException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final gw = ref.watch(cloudGatewayProvider);
    final user = _user;
    return Scaffold(
      appBar: DtAppBar(title: Text(t['support_title']), actions: [
        IconButton(key: const ValueKey('support-help'), tooltip: t['help_title'], icon: const Icon(Icons.menu_book_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()))),
      ]),
      body: gw == null || user == null
          ? Center(child: Text(t['blk_internet_b']))
          : Column(children: [
              Expanded(
                child: StreamBuilder<List<SupportMessage>>(
                  stream: gw.watchSupport(user.uid),
                  builder: (context, snap) {
                    final msgs = snap.data ?? const <SupportMessage>[];
                    if (msgs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t['support_empty'], textAlign: TextAlign.center)));
                    return ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final m in msgs)
                          Align(
                            alignment: m.fromAdmin ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                            child: Card(
                              color: m.fromAdmin ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.primaryContainer,
                              child: Padding(padding: const EdgeInsets.all(10), child: Text(m.text)),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Expanded(child: TextField(key: const Key('support_text'), controller: _text, minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: t['support_hint']))),
                    if (_whatsapp.isNotEmpty)
                      IconButton(
                        key: const ValueKey('support-whatsapp'),
                        tooltip: t['support_whatsapp'],
                        onPressed: () => sendViaWhatsApp(ref, _whatsapp, '${_restaurant.isEmpty ? '' : '$_restaurant: '}${_text.text.trim()}'.trim()),
                        icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                      ),
                    IconButton(key: const Key('support_send'), onPressed: _send, icon: const Icon(Icons.send)),
                  ]),
                ),
              ),
            ]),
    );
  }
}
