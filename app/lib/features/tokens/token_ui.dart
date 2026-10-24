import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../domain/money.dart';
import '../../domain/token.dart';
import '../common/dialogs.dart';

/// Short, translated names of the token kinds.
String kindName(Strings t, TokenKind k) => t['kind_${k.name}'];
String kindHelp(Strings t, TokenKind k) => t['kind_${k.name}_d'];

IconData kindIcon(TokenKind k) => switch (k) {
      TokenKind.order => Icons.confirmation_number_outlined,
      TokenKind.product => Icons.fastfood_outlined,
      TokenKind.unit => Icons.exposure_plus_1,
      TokenKind.price => Icons.receipt_long_outlined,
      TokenKind.tandoor => Icons.local_fire_department_outlined,
      TokenKind.stall => Icons.storefront_outlined,
      TokenKind.coupon => Icons.card_giftcard_outlined,
    };

/// Starting values of a new token type of this kind.
TokenRule newRule(TokenKind k, String id, Strings t) => TokenRule(
      id: id,
      kind: k,
      name: switch (k) {
        TokenKind.tandoor => 'Tandoor',
        TokenKind.stall => 'Stall 1',
        TokenKind.coupon => 'Coupon',
        _ => kindName(t, k),
      },
      prefix: switch (k) {
        TokenKind.order => 'A',
        TokenKind.product => 'P',
        TokenKind.unit => 'U',
        TokenKind.price => 'R',
        TokenKind.tandoor => 'T',
        TokenKind.stall => 'S',
        TokenKind.coupon => 'C',
      },
      station: switch (k) {
        TokenKind.tandoor => 'Tandoor',
        TokenKind.stall => 'Stall 1',
        TokenKind.coupon => 'Coupon',
        _ => '',
      },
      collectText: k == TokenKind.stall ? 'Collect from Stall 1' : (k == TokenKind.tandoor ? 'Collect from the Tandoor counter' : ''),
    );

/// Prints a TEST slip (sample data) on one printer, so the owner can see the real paper.
Future<void> testPrinter(BuildContext context, WidgetRef ref, Map<String, Object?> printer) async {
  final t = Strings.of(context);
  final svc = ref.read(tokenServiceProvider);
  final design = await svc.template('classic');
  final cur = ref.read(businessProvider).value?.currency ?? Currency.pkr;
  final name = ref.read(businessProvider).value?.name ?? '';
  final print = ref.read(printServiceProvider);
  final jobs = await print.queueTestSlip(design, (_) => sampleSlip(TokenKind.order, businessName: name, currency: cur), printerId: printer['id'] as String);
  if (jobs.isNotEmpty) print.processQueue();
  if (context.mounted) showMessage(context, jobs.isEmpty ? t['no_printer'] : t['print_queued']);
}
