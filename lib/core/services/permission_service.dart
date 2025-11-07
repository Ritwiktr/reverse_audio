import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  const PermissionService();

  Future<bool> hasMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isMicrophonePermissionPermanentlyDenied() async {
    try {
      final status = await Permission.microphone.status;
      return status.isPermanentlyDenied;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestMicrophone() async {
    try {
      final result = await Permission.microphone.request();
      return result.isGranted;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestImportPermissions() async {
    return true;
  }
}
