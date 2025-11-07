import 'dart:io';

import 'package:path/path.dart' as p;

class AudioUtils {
  const AudioUtils._();

  static String sanitizeFileName(String filePath) {
    final base = p.basenameWithoutExtension(filePath);
    return base.replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '_');
  }

  static String changeExtension(File file, String newExtension) {
    final directory = file.parent.path;
    final sanitizedName = sanitizeFileName(file.path);
    return p.join(directory, '$sanitizedName$newExtension');
  }

  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
