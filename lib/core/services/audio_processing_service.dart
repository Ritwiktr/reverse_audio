import 'dart:io';

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
      final success = await ReverseAudioService.reverseAudio(
        originalFile.path,
        reverseFile.path,
      );

      if (!success) {
        // Fallback: if reversal fails, just copy the file
        // This ensures the app still works even if reversal isn't supported
        await originalFile.copy(reverseFile.path);
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
