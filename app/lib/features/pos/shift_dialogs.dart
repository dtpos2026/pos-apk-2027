import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../domain/money.dart';
import '../reports/day_close_screen.dart';

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

/// "Close day" on the sell screen: opens the end-of-day report for the open business date. Closing it ends the cash drawer
/// for the day too, and the next sale starts a fresh day (Today's sales shows zero; the closed day stays in Reports).
Future<void> closeDayFromPos(BuildContext context, WidgetRef ref) async {
  final date = await ref.read(dbHelperProvider).openBusinessDate();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DayCloseScreen(date: date)));
  await ref.read(shiftProvider.notifier).refresh();
}
