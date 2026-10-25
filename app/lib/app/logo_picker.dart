import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Lets the owner choose a logo picture. A seam so tests can supply a picture without the Android picker.
abstract class LogoPicker {
  Future<Uint8List?> pick();

  /// Takes a new photo with the camera (customer pictures). Pickers without a camera fall back to the gallery.
  Future<Uint8List?> capture() => pick();
}

class GalleryLogoPicker implements LogoPicker {
  const GalleryLogoPicker();
  @override
  Future<Uint8List?> pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
    return x?.readAsBytes();
  }

  @override
  Future<Uint8List?> capture() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, preferredCameraDevice: CameraDevice.front);
    return x?.readAsBytes();
  }
}
