import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'csv.dart';

/// Reads the first sheet of an .xlsx file as CSV text, so the same validated importer handles Excel and CSV.
/// An .xlsx is a zip of XML parts: shared strings (xl/sharedStrings.xml) and one XML file per sheet.
/// Handles text (shared, inline, formula strings), numbers and booleans. Returns null if the file is not a workbook.
String? xlsxToCsv(Uint8List bytes) {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? file(String name) => zip.files.where((f) => f.isFile && f.name == name).firstOrNull;
    String? read(ArchiveFile? f) => f == null ? null : _utf8(f.content as List<int>);

    final sheets = zip.files.where((f) => f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)).toList()
      ..sort((a, b) => _num(a.name).compareTo(_num(b.name)));
    if (sheets.isEmpty) return null;

    final shared = <String>[];
    final ss = read(file('xl/sharedStrings.xml'));
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    final doc = XmlDocument.parse(_utf8(sheets.first.content as List<int>));
    final rows = <List<String>>[];
    for (final row in doc.findAllElements('row')) {
      final cells = <int, String>{};
      var next = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? next : _column(ref);
        next = col + 1;
        cells[col] = _cellText(c, shared);
      }
      if (cells.isEmpty) continue;
      final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
      final list = [for (var i = 0; i < width; i++) cells[i] ?? ''];
      while (list.isNotEmpty && list.last.isEmpty) {
        list.removeLast();
      }
      if (list.isNotEmpty) rows.add(list);
    }
    return rows.map((r) => r.map(csvEscape).join(',')).join('\n');
  } catch (_) {
    return null;
  }
}

String _utf8(List<int> b) => utf8.decode(b, allowMalformed: true).replaceFirst('\uFEFF', '');

int _num(String name) => int.parse(RegExp(r'sheet(\d+)\.xml').firstMatch(name)!.group(1)!);

/// "AB12" -> 27 (zero based column index).
int _column(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) {
      n = n * 26 + (u - 64);
    } else {
      break;
    }
  }
  return n - 1;
}

String _cellText(XmlElement c, List<String> shared) {
  final t = c.getAttribute('t');
  final v = c.getElement('v')?.innerText ?? '';
  switch (t) {
    case 's':
      final i = int.tryParse(v);
      return i != null && i < shared.length ? shared[i] : '';
    case 'inlineStr':
      return c.findAllElements('t').map((e) => e.innerText).join();
    case 'b':
      return v == '1' ? 'yes' : 'no';
    case 'str':
    case 'e':
      return v;
    default:
      final d = double.tryParse(v);
      if (d == null) return v;
      return d == d.roundToDouble() && d.abs() < 1e15 ? '${d.toInt()}' : '$d';
  }
}
