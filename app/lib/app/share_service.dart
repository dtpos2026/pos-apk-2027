import 'package:share_plus/share_plus.dart';

/// Shares text (a bill) through the phone's share sheet, so the owner can pick WhatsApp. A seam for tests.
abstract class ShareService {
  Future<void> shareText(String text, {String? subject});
  Future<void> shareFile(String path, {String? mimeType, String? subject});
}

class SystemShareService implements ShareService {
  const SystemShareService();
  @override
  Future<void> shareText(String text, {String? subject}) => SharePlus.instance.share(ShareParams(text: text, subject: subject));

  @override
  Future<void> shareFile(String path, {String? mimeType, String? subject}) => SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: mimeType)], subject: subject));
}
