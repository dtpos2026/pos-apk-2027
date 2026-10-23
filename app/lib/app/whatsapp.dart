import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/phone.dart';
import 'providers.dart';

/// Opens WhatsApp with a ready message (main() supplies Android). null = not available (tests, desktop).
final whatsAppOpenerProvider = Provider<Future<bool> Function(String phoneIntl, String text)?>((ref) => null);

/// Opens a WhatsApp chat with [phone] and [text] typed in; the person presses Send themselves.
/// Falls back to the share sheet (pick WhatsApp there) when the number is unusable or WhatsApp is not installed.
Future<void> sendViaWhatsApp(WidgetRef ref, String? phone, String text) async {
  final currency = ref.read(businessProvider).value?.currency.code ?? 'PKR';
  final intl = phone == null ? null : internationalPhone(phone, countryCode: callingCodeFor(currency));
  final open = ref.read(whatsAppOpenerProvider);
  if (intl != null && open != null && await open(intl, text)) return;
  await ref.read(shareServiceProvider).shareText(text);
}

/// Asks for a phone number (pre-filled when known). null = cancelled.
Future<String?> askPhone(BuildContext context, {String? initial, required String title, required String label, required String ok, required String cancel}) {
  final c = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(key: const ValueKey('wa-phone'), controller: c, keyboardType: TextInputType.phone, autofocus: true, decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.phone_outlined))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(cancel)),
        FilledButton(key: const ValueKey('wa-phone-ok'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ok)),
      ],
    ),
  );
}
