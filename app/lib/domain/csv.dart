/// RFC 4180 CSV parser: quoted fields, escaped quotes (""), commas and newlines inside quotes, CRLF or LF, optional BOM.
List<List<String>> parseCsv(String input) {
  var s = input;
  if (s.startsWith('﻿')) s = s.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldStarted = false;

  void endField() {
    row.add(field.toString());
    field.clear();
    fieldStarted = false;
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row); // skip blank lines
    row = <String>[];
  }

  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && !fieldStarted) {
      inQuotes = true;
      fieldStarted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
      fieldStarted = true;
    }
  }
  if (inQuotes) throw const FormatException('Unterminated quoted field');
  if (fieldStarted || field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

String csvEscape(String v) => (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) ? '"${v.replaceAll('"', '""')}"' : v;
