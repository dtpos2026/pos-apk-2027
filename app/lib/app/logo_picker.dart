import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Lets the owner choose a logo picture. A seam so tests can supply a picture without the Android picker.
abstract class LogoPicker {
  Future<Uint8List?> pick();
}

class GalleryLogoPicker implements LogoPicker {
  const GalleryLogoPicker();
  @override
  Future<Uint8List?> pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
    return x?.readAsBytes();
  }
}
