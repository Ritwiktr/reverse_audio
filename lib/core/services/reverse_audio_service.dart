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
      debugPrint('ReverseAudioService: Platform not supported (web/desktop)');
      // For web/desktop, return false to use fallback
      return false;
    }

    // Verify input file exists
    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      debugPrint('ReverseAudioService: Input file does not exist: $inputPath');
      return false;
    }

    final inputSize = await inputFile.length();
    debugPrint('ReverseAudioService: Input file size: $inputSize bytes');

    if (inputSize == 0) {
      debugPrint('ReverseAudioService: Input file is empty');
      return false;
    }

    try {
      debugPrint(
        'ReverseAudioService: Calling platform channel to reverse audio',
      );
      final result = await _channel.invokeMethod<bool>('reverseAudio', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });

      final success = result ?? false;
      debugPrint('ReverseAudioService: Platform channel returned: $success');
      return success;
    } catch (e, stackTrace) {
      debugPrint('ReverseAudioService: Error reversing audio: $e');
      debugPrint('ReverseAudioService: Stack trace: $stackTrace');
      return false;
    }
  }
}
