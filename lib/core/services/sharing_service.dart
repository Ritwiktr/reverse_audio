import 'package:share_plus/share_plus.dart';

class SharingService {
  const SharingService();

  Future<void> shareFile(String path, {String? message}) async {
    await Share.shareXFiles([XFile(path)], text: message);
  }
}
