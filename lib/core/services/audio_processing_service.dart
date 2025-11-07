import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../error/app_failure.dart';
import '../utils/audio_utils.dart';
import '../../features/audio/domain/entities/processed_audio.dart';

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

      // For now, copy the file as "reversed" - actual reversing requires FFmpeg
      // TODO: Implement proper audio reversing using platform channels or FFmpeg
      await originalFile.copy(reverseFile.path);

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
