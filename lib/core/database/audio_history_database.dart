import '../../features/audio/domain/entities/processed_audio.dart';

class AudioHistoryEntry {
  AudioHistoryEntry({required this.processedAudio, required this.createdAt});

  final ProcessedAudio processedAudio;
  final DateTime createdAt;
}

class AudioHistoryDatabase {
  final List<AudioHistoryEntry> _entries = [];

  List<AudioHistoryEntry> get entries => List.unmodifiable(_entries);

  void add(ProcessedAudio audio) {
    _entries.insert(
      0,
      AudioHistoryEntry(processedAudio: audio, createdAt: DateTime.now()),
    );
    if (_entries.length > 20) {
      _entries.removeRange(20, _entries.length);
    }
  }
}
