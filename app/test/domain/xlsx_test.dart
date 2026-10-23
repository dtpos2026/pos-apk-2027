import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dt_food_pos/domain/csv.dart';
import 'package:dt_food_pos/domain/xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a real .xlsx (a zip of XML parts) the way Excel lays it out.
Uint8List workbook({required String sheetXml, String? sharedStrings, int sheetNo = 1}) {
  final a = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'))
    ..addFile(ArchiveFile.string('xl/workbook.xml', '<workbook/>'))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet$sheetNo.xml', '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>$sheetXml</sheetData></worksheet>'));
  if (sharedStrings != null) a.addFile(ArchiveFile.string('xl/sharedStrings.xml', '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">$sharedStrings</sst>'));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  test('shared strings, numbers, inline strings, booleans, gaps and rich text become CSV', () {
    final csv = xlsxToCsv(workbook(
      sharedStrings: '<si><t>category</t></si><si><t>name</t></si><si><t>price</t></si><si><t>Chicken, boneless</t></si><si><t>Desi</t></si><si><t>چکن کڑاہی</t></si><si><r><t>Cola </t></r><r><t>500ml</t></r></si>',
      sheetXml: '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c><c r="D1" t="inlineStr"><is><t>sku</t></is></c><c r="E1" t="s"><v>0</v></c></row>'
          '<row r="2"><c r="A2" t="s"><v>4</v></c><c r="B2" t="s"><v>3</v></c><c r="C2"><v>1250.5</v></c><c r="D2" t="str"><v>DSI-1</v></c></row>'
          '<row r="3"><c r="A3" t="s"><v>4</v></c><c r="B3" t="s"><v>5</v></c><c r="C3"><v>1800</v></c></row>'
          '<row r="4"><c r="B4" t="s"><v>6</v></c><c r="C4"><v>100</v></c><c r="E4" t="b"><v>1</v></c></row>'
          '<row r="5"/>',
    ))!;
    final rows = parseCsv(csv);
    expect(rows[0], ['category', 'name', 'price', 'sku', 'category']);
    expect(rows[1], ['Desi', 'Chicken, boneless', '1250.5', 'DSI-1']);
    expect(rows[2], ['Desi', 'چکن کڑاہی', '1800']);
    expect(rows[3], ['', 'Cola 500ml', '100', '', 'yes']); // column A left empty: the later columns keep their place
    expect(rows.length, 4); // the empty row is dropped
  });

  test('reads the lowest-numbered sheet', () {
    final csv = xlsxToCsv(workbook(sheetNo: 3, sheetXml: '<row r="1"><c r="A1" t="inlineStr"><is><t>only</t></is></c></row>'))!;
    expect(csv, 'only');
  });

  test('columns beyond Z are placed correctly', () {
    final csv = xlsxToCsv(workbook(sheetXml: '<row r="1"><c r="A1"><v>1</v></c><c r="AB1"><v>2</v></c></row>'))!;
    final cells = parseCsv(csv).single;
    expect(cells.length, 28);
    expect([cells.first, cells.last], ['1', '2']);
  });

  test('not a workbook, or a zip without sheets, gives null', () {
    expect(xlsxToCsv(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(xlsxToCsv(Uint8List.fromList(ZipEncoder().encode(Archive()..addFile(ArchiveFile.string('hello.txt', 'hi'))))), isNull);
    expect(xlsxToCsv(Uint8List.fromList(utf8.encode('name,price'))), isNull);
  });

  test('the converted sheet imports through the same CSV rules (template columns)', () {
    final csv = xlsxToCsv(workbook(
      sheetXml: '<row r="1"><c r="A1" t="inlineStr"><is><t>category</t></is></c><c r="B1" t="inlineStr"><is><t>name</t></is></c><c r="C1" t="inlineStr"><is><t>price</t></is></c></row>'
          '<row r="2"><c r="A2" t="inlineStr"><is><t>Burgers</t></is></c><c r="B2" t="inlineStr"><is><t>Zinger</t></is></c><c r="C2"><v>450</v></c></row>',
    ))!;
    expect(csv, 'category,name,price\nBurgers,Zinger,450');
  });
}
