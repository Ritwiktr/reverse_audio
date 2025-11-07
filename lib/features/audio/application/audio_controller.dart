import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/audio_history_database.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/services/audio_processing_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/sharing_service.dart';
import '../../../core/usecases/share_audio_usecase.dart';
import '../domain/entities/processed_audio.dart';

enum PlaybackDirection { forward, reverse }

class AudioController extends ChangeNotifier {
  AudioController({
    AudioProcessingService? processingService,
    PermissionService? permissionService,
    SharingService? sharingService,
    AudioHistoryDatabase? historyDatabase,
  }) : _processingService = processingService ?? const AudioProcessingService(),
       _permissionService = permissionService ?? const PermissionService(),
       _historyDatabase = historyDatabase ?? AudioHistoryDatabase(),
       _shareAudioUseCase = ShareAudioUseCase(
         sharingService ?? const SharingService(),
       );

  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioProcessingService _processingService;
  final PermissionService _permissionService;
  final AudioHistoryDatabase _historyDatabase;
  final ShareAudioUseCase _shareAudioUseCase;

  ProcessedAudio? _processedAudio;
  PlaybackDirection _direction = PlaybackDirection.forward;
  bool _isProcessing = false;
  bool _isRecording = false;
  bool _initialized = false;
  bool _isPickingFile = false;
  double _speed = AppConstants.defaultSpeed;
  double _pitch = AppConstants.defaultPitch;
  String? _error;

  StreamSubscription<ProcessingState>? _processingSubscription;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration? get duration => _player.duration;

  bool get hasAudio => _processedAudio != null;
  bool get isProcessing => _isProcessing;
  bool get isRecording => _isRecording;
  bool get isPickingFile => _isPickingFile;
  bool get isPlaying => _player.playing;
  bool get canPlay => hasAudio && !_isProcessing && !_isRecording;
  double get speed => _speed;
  double get pitch => _pitch;
  bool get isLooping => _player.loopMode == LoopMode.one;
  PlaybackDirection get direction => _direction;
  String? get errorMessage => _error;
  List<AudioHistoryEntry> get history => _historyDatabase.entries;

  Future<void> init() async {
    if (_initialized) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _processingSubscription = _player.processingStateStream.listen(
      (_) => notifyListeners(),
    );
    _initialized = true;
  }

  Future<void> requestMicrophonePermissionOnStart() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _permissionService.requestMicrophone();
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    try {
      final permissionGranted = await _permissionService.requestMicrophone();
      final recorderHasPermission = await _recorder.hasPermission();

      if (!permissionGranted && !recorderHasPermission) {
        final isPermanentlyDenied = await _permissionService
            .isMicrophonePermissionPermanentlyDenied();

        if (isPermanentlyDenied) {
          _setError(
            'Microphone permission was denied. Please enable it in Settings > Privacy & Security > Microphone.',
          );
        } else {
          final directory = await getTemporaryDirectory();
          final filePath = p.join(
            directory.path,
            'recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
          );

          try {
            await _recorder.start(
              const RecordConfig(
                encoder: AudioEncoder.aacLc,
                bitRate: 128000,
                sampleRate: 44100,
                numChannels: 2,
              ),
              path: filePath,
            );
            _isRecording = true;
            _error = null;
            notifyListeners();
            return;
          } catch (recorderError) {
            final errorMsg = recorderError.toString().toLowerCase();
            if (errorMsg.contains('permission') ||
                errorMsg.contains('denied')) {
              _setError(
                'Microphone permission is required. Please enable it in Settings > Privacy & Security > Microphone.',
              );
            } else {
              _setError('Failed to start recording: $recorderError');
            }
            return;
          }
        }
        return;
      }

      final directory = await getTemporaryDirectory();
      final filePath = p.join(
        directory.path,
        'recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 2,
        ),
        path: filePath,
      );
      _isRecording = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.toLowerCase().contains('permission') ||
          errorMsg.toLowerCase().contains('denied')) {
        _setError(
          'Microphone permission denied. Please enable it in your device Settings > Privacy > Microphone.',
        );
      } else {
        _setError('Failed to start recording: $errorMsg');
      }
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      notifyListeners();
      if (path != null) {
        await _prepareAudioFiles(File(path));
      }
    } catch (e) {
      _setError('Failed to stop recording: $e');
    }
  }

  Future<void> pickAudio() async {
    if (_isProcessing || _isRecording || _isPickingFile) return;

    try {
      _isPickingFile = true;
      notifyListeners();

      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null || filePath.isEmpty) {
        _setError('Invalid file selected. Please try again.');
        return;
      }

      final file = File(filePath);
      if (!file.existsSync()) {
        _setError('Selected file does not exist.');
        return;
      }

      await _prepareAudioFiles(file);
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('multiple_request') ||
          errorMsg.contains('Cancelled') ||
          errorMsg.contains('cancel')) {
        return;
      }
      _setError(
        'Failed to import audio: ${errorMsg.isNotEmpty ? errorMsg : "Unknown error"}',
      );
    } finally {
      _isPickingFile = false;
      notifyListeners();
    }
  }

  Future<void> seek(Duration position) async {
    if (!hasAudio) return;
    try {
      await _player.seek(position);
    } catch (e) {
      _setError('Unable to seek: $e');
    }
  }

  Future<void> togglePlayback() async {
    if (!canPlay) return;
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e) {
      _setError('Playback failed: $e');
    }
    notifyListeners();
  }

  Future<void> stopPlayback() async {
    await _player.stop();
    notifyListeners();
  }

  Future<void> setDirection(PlaybackDirection direction) async {
    if (_direction == direction) return;
    _direction = direction;
    await _loadCurrentDirection();
    notifyListeners();
  }

  Future<void> setSpeed(double value) async {
    _speed = value;
    try {
      await _player.setSpeed(value);
    } catch (e) {
      _setError('Unable to set speed: $e');
    }
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    _pitch = value;
    try {
      await _player.setPitch(value);
    } catch (e) {
      _setError('Unable to set pitch: $e');
    }
    notifyListeners();
  }

  Future<void> toggleLoop(bool enabled) async {
    await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  Future<void> shareCurrent() async {
    final path = _currentPath;
    if (path == null) return;
    try {
      await _shareAudioUseCase(path, message: 'Check out my reversed audio!');
    } catch (e) {
      _setError('Unable to share audio: $e');
    }
  }

  String? get _currentPath {
    if (!hasAudio) return null;
    return _direction == PlaybackDirection.forward
        ? _processedAudio?.forwardPath
        : _processedAudio?.reversePath;
  }

  Future<void> _prepareAudioFiles(File originalFile) async {
    _setProcessing(true);
    try {
      final processedAudio = await _processingService.process(originalFile);
      _processedAudio = processedAudio;
      _direction = PlaybackDirection.forward;
      _error = null;
      _historyDatabase.add(processedAudio);
      await _loadCurrentDirection();
    } on AppFailure catch (failure) {
      _setError(failure.message);
    } catch (e) {
      _setError('Unable to process audio: $e');
    } finally {
      _setProcessing(false);
    }
  }

  Future<void> _loadCurrentDirection() async {
    final path = _currentPath;
    if (path == null) return;
    try {
      await _player.stop();
      await _player.setFilePath(path);
      await _player.setSpeed(_speed);
      await _player.setPitch(_pitch);
      await _player.setLoopMode(isLooping ? LoopMode.one : LoopMode.off);
    } catch (e) {
      _setError('Failed to load audio: $e');
    }
  }

  void _setProcessing(bool value) {
    _isProcessing = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _processingSubscription?.cancel();
    _player.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
