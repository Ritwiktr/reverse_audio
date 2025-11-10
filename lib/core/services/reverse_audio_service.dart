import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ReverseAudioService {
  static const MethodChannel _channel = MethodChannel(
    'com.reverseaudio.reverse',
  );

  /// Reverses an audio file
  /// [inputPath] - Path to the input audio file
  /// [outputPath] - Path where the reversed audio file should be saved
  /// Returns true if successful, false otherwise
  static Future<bool> reverseAudio(String inputPath, String outputPath) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      // For web/desktop, return false to use fallback
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('reverseAudio', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('ReverseAudioService: Error reversing audio: $e');
      return false;
    }
  }
}
