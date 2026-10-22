import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../domain/money.dart';

Future<int?> _askAmount(BuildContext context, WidgetRef ref, String title, String label, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  final t = Strings.of(context);
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(key: const ValueKey('amount-field'), controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))], decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
        FilledButton(key: const ValueKey('amount-ok'), onPressed: () => Navigator.pop(ctx, parseMinor(c.text.isEmpty ? '0' : c.text, currency: ref.currency)), child: Text(t['save'])),
      ],
    ),
  );
}

Future<void> openShiftDialog(BuildContext context, WidgetRef ref) async {
  final t = Strings.of(context);
  final amount = await _askAmount(context, ref, t['open_shift'], t['opening_cash'], initial: '0');
  if (amount == null) return;
  await ref.read(shiftProvider.notifier).open(amount);
}

Future<void> closeShiftDialog(BuildContext context, WidgetRef ref) async {
  final t = Strings.of(context);
  final amount = await _askAmount(context, ref, t['close_shift'], t['counted_cash']);
  if (amount == null) return;
  final variance = await ref.read(shiftProvider.notifier).close(amount);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t['variance']),
      content: Text(ref.money(variance), key: const ValueKey('variance'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: variance == 0 ? Colors.green : Theme.of(ctx).colorScheme.error)),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
