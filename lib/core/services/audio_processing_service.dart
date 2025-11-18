import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../error/app_failure.dart';
import '../utils/audio_utils.dart';
import '../../features/audio/domain/entities/processed_audio.dart';
import 'reverse_audio_service.dart';

class AudioProcessingService {
  const AudioProcessingService();

  Future<ProcessedAudio> process(File originalFile) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final sanitizedName = AudioUtils.sanitizeFileName(originalFile.path);
      final forwardFile = File(
        p.join(
          docs.path,
          '${sanitizedName}_source${p.extension(originalFile.path)}',
        ),
      );
      final reverseFile = File(
        p.join(
          docs.path,
          '${sanitizedName}_reverse${p.extension(originalFile.path)}',
        ),
      );

      await forwardFile.parent.create(recursive: true);
      if (reverseFile.existsSync()) {
        await reverseFile.delete();
      }
      if (originalFile.path != forwardFile.path) {
        await originalFile.copy(forwardFile.path);
      }

      // Reverse the audio file using platform channel
      debugPrint('AudioProcessingService: Attempting to reverse audio');
      debugPrint('AudioProcessingService: Input: ${originalFile.path}');
      debugPrint('AudioProcessingService: Output: ${reverseFile.path}');

      final success = await ReverseAudioService.reverseAudio(
        originalFile.path,
        reverseFile.path,
      );

      if (!success) {
        debugPrint(
          'AudioProcessingService: Reverse failed, using fallback (copy)',
        );
        // Fallback: if reversal fails, just copy the file
        // This ensures the app still works even if reversal isn't supported
        await originalFile.copy(reverseFile.path);
      } else {
        debugPrint('AudioProcessingService: Audio reversed successfully');

        // Verify the reversed file was created and has content
        if (!reverseFile.existsSync()) {
          debugPrint(
            'AudioProcessingService: Reversed file does not exist, using fallback',
          );
          await originalFile.copy(reverseFile.path);
        } else {
          final reversedSize = await reverseFile.length();
          debugPrint(
            'AudioProcessingService: Reversed file size: $reversedSize bytes',
          );

          if (reversedSize == 0) {
            debugPrint(
              'AudioProcessingService: Reversed file is empty, using fallback',
            );
            await reverseFile.delete();
            await originalFile.copy(reverseFile.path);
          }
        }
      }

      return ProcessedAudio(
        forwardPath: forwardFile.path,
        reversePath: reverseFile.path,
      );
    } catch (e) {
      if (e is AppFailure) {
        rethrow;
      }
      throw AppFailure('Unable to process audio', cause: e);
    }
  }
}
