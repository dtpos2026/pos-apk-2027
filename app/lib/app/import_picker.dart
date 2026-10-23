import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Lets the owner choose a menu file (.csv or .xlsx). A seam so tests can supply file contents directly.
abstract class ImportFilePicker {
  Future<({String name, Uint8List bytes})?> pick();
}

class SystemImportFilePicker implements ImportFilePicker {
  const SystemImportFilePicker();
  @override
  Future<({String name, Uint8List bytes})?> pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['csv', 'xlsx']);
    if (f == null) return null;
    return (name: f.name, bytes: await f.readAsBytes());
  }
}
