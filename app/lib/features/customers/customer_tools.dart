import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/queries.dart' show loadBusiness;
import '../../domain/customer_export.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';
import '../common/pdf_brand_loader.dart';

/// Saves the customer list (as shown by the search) to the phone's Downloads as CSV (Excel) or PDF, then opens the share sheet.
Future<void> exportCustomers(BuildContext context, WidgetRef ref, {required bool pdf, String search = ''}) async {
  final t = Strings.of(context);
  final list = await ref.read(customerServiceProvider).list(search: search);
  final biz = await loadBusiness(ref.read(databaseProvider));
  final cur = biz?.currency ?? Currency.pkr;
  final dir = ref.read(exportDirProvider)..createSync(recursive: true);
  final File f;
  if (pdf) {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic.ttf'));
    final bytes = await buildCustomersPdf(businessName: biz?.name ?? '', customers: list, currency: cur, generatedAt: ref.read(clockProvider)(), script: font, identity: await loadPdfBrand(ref));
    f = File('${dir.path}/customers.pdf')..writeAsBytesSync(bytes);
  } else {
    f = File('${dir.path}/customers.csv')..writeAsStringSync('\u{FEFF}${customersCsv(list, currency: cur)}'); // BOM so Excel reads Urdu names
  }
  final name = f.path.split('/').last;
  final mime = pdf ? 'application/pdf' : 'text/csv';
  try {
    final where = await ref.read(phoneFileSaverProvider).save(path: f.path, name: name, mime: mime);
    if (context.mounted) showMessage(context, '${t['saved_to']}: $where');
  } catch (e) {
    if (context.mounted) showMessage(context, '${t['save_failed']}: $e');
  }
  await ref.read(shareServiceProvider).shareFile(f.path, mimeType: mime, subject: 'customers');
}
