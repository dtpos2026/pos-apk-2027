import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/pdf_brand.dart';
import '../../app/providers.dart';

/// The restaurant's logo and contact plus the Digital Target mark, for the top of every PDF.
Future<PdfBrand> loadPdfBrand(WidgetRef ref) async {
  final b = await loadBusiness(ref.read(databaseProvider));
  Uint8List? logo;
  final path = b?.logoPath;
  if (path != null && File(path).existsSync()) {
    try {
      logo = File(path).readAsBytesSync();
    } catch (_) {}
  }
  Uint8List? mark;
  try {
    mark = (await rootBundle.load('assets/brand/dt_mark_red.png')).buffer.asUint8List();
  } catch (_) {}
  return PdfBrand(name: b?.name ?? '', address: b?.address, phone: b?.phone, logo: logo, dtMark: mark);
}
