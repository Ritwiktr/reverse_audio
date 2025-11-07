import '../services/sharing_service.dart';

class ShareAudioUseCase {
  ShareAudioUseCase(this._sharingService);

  final SharingService _sharingService;

  Future<void> call(String path, {String? message}) {
    return _sharingService.shareFile(path, message: message);
  }
}
