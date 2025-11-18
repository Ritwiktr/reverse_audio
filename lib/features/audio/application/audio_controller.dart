import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/audio_history_database.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/services/audio_processing_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/pitch_service.dart';
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
  bool _iosIsPlaying = false;
  bool _iosIsLooping = false;
  Duration _iosPosition = Duration.zero;
  Duration? _iosDuration;

  StreamSubscription<ProcessingState>? _processingSubscription;
  Timer? _iosPositionTimer;

  // Use platform channel player on iOS and Android, just_audio on web
  bool get _shouldUsePlatformPlayer =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Stream<Duration> get positionStream {
    if (_shouldUsePlatformPlayer) {
      return _iosPositionStream;
    }
    return _player.positionStream;
  }

  Stream<Duration?> get durationStream {
    if (_shouldUsePlatformPlayer) {
      return _iosDurationStream;
    }
    return _player.durationStream;
  }

  Stream<Duration> get bufferedPositionStream {
    if (_shouldUsePlatformPlayer) {
      return _iosPositionStream;
    }
    return _player.bufferedPositionStream;
  }

  Stream<PlayerState> get playerStateStream {
    if (_shouldUsePlatformPlayer) {
      return _iosPlayerStateStream;
    }
    return _player.playerStateStream;
  }

  Duration? get duration {
    if (_shouldUsePlatformPlayer) {
      return _iosDuration;
    }
    return _player.duration;
  }

  bool get hasAudio => _processedAudio != null;
  bool get isProcessing => _isProcessing;
  bool get isRecording => _isRecording;
  bool get isPickingFile => _isPickingFile;
  bool get isPlaying {
    if (_shouldUsePlatformPlayer) {
      return _iosIsPlaying;
    }
    return _player.playing;
  }

  bool get canPlay => hasAudio && !_isProcessing && !_isRecording;
  double get speed => _speed;
  double get pitch => _pitch;
  bool get isLooping {
    if (_shouldUsePlatformPlayer) {
      return _iosIsLooping;
    }
    return _player.loopMode == LoopMode.one;
  }

  PlaybackDirection get direction => _direction;
  String? get errorMessage => _error;
  List<AudioHistoryEntry> get history => _historyDatabase.entries;
  bool get isPitchSupported =>
      true; // Platform channel supports pitch on iOS and Android

  // iOS position stream
  Stream<Duration> get _iosPositionStream async* {
    while (true) {
      yield _iosPosition;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // iOS duration stream
  Stream<Duration?> get _iosDurationStream async* {
    yield _iosDuration;
    // Keep stream alive and emit updates when duration changes
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      yield _iosDuration;
    }
  }

  // iOS player state stream
  Stream<PlayerState> get _iosPlayerStateStream async* {
    while (true) {
      // Create a PlayerState compatible with just_audio
      // PlayerState constructor: PlayerState(bool playing, ProcessingState processingState)
      yield PlayerState(
        _iosIsPlaying,
        _iosIsPlaying ? ProcessingState.ready : ProcessingState.idle,
      );
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

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
      _error = null;
      notifyListeners();

      // On iOS, use FileType.any which is the most reliable
      // Don't use fallbacks as they cause "multiple_request" errors
      FilePickerResult? result;

      if (!kIsWeb && Platform.isIOS) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
          withData: false,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.audio,
          allowMultiple: false,
          withData: kIsWeb, // Only use withData on web
        );
      }

      if (result == null || result.files.isEmpty) {
        _isPickingFile = false;
        notifyListeners();
        return;
      }

      final pickedFile = result.files.single;

      if (kIsWeb) {
        // Web platform: use bytes
        if (pickedFile.bytes == null || pickedFile.bytes!.isEmpty) {
          _setError('Invalid file selected. Please try again.');
          return;
        }

        // Save bytes to a temporary file
        try {
          final directory = await getTemporaryDirectory();
          final extension = pickedFile.extension?.isNotEmpty == true
              ? '.${pickedFile.extension}'
              : '.mp3';
          final fileName = pickedFile.name.isNotEmpty
              ? pickedFile.name
              : 'audio_${DateTime.now().millisecondsSinceEpoch}$extension';
          final filePath = p.join(directory.path, fileName);
          final file = File(filePath);
          await file.writeAsBytes(pickedFile.bytes!);
          await _prepareAudioFiles(file);
        } catch (e) {
          _setError('Failed to process file on web: $e');
          return;
        }
      } else {
        // Mobile/Desktop platforms: use file path
        final filePath = pickedFile.path;

        if (filePath == null || filePath.isEmpty) {
          // On iOS, if path is not available, we need to use bytes
          // This requires picking again with withData: true
          if (Platform.isIOS) {
            try {
              // Re-pick with data on iOS if path is not available
              final resultWithData = await FilePicker.platform.pickFiles(
                type: FileType.audio,
                allowMultiple: false,
                withData: true,
              );

              if (resultWithData != null &&
                  resultWithData.files.isNotEmpty &&
                  resultWithData.files.single.bytes != null &&
                  resultWithData.files.single.bytes!.isNotEmpty) {
                final bytes = resultWithData.files.single.bytes!;
                final directory = await getTemporaryDirectory();
                final extension = pickedFile.extension?.isNotEmpty == true
                    ? '.${pickedFile.extension}'
                    : '.mp3';
                final fileName = pickedFile.name.isNotEmpty
                    ? pickedFile.name
                    : 'audio_${DateTime.now().millisecondsSinceEpoch}$extension';
                final tempPath = p.join(directory.path, fileName);
                final file = File(tempPath);
                await file.writeAsBytes(bytes);
                await _prepareAudioFiles(file);
                return;
              }
            } catch (e) {
              _setError('Failed to load file: $e');
              return;
            }
          }

          _setError('Invalid file selected. Please try again.');
          return;
        }

        // On iOS, file paths from document picker are often temporary
        // Copy the file to a permanent location
        if (Platform.isIOS) {
          try {
            final sourceFile = File(filePath);
            if (!sourceFile.existsSync()) {
              _setError(
                'Selected file does not exist. Please try selecting the file again.',
              );
              return;
            }

            // Copy to app's temporary directory for processing
            final directory = await getTemporaryDirectory();
            final extension = pickedFile.extension?.isNotEmpty == true
                ? '.${pickedFile.extension}'
                : '.mp3';
            final fileName = pickedFile.name.isNotEmpty
                ? pickedFile.name
                : 'audio_${DateTime.now().millisecondsSinceEpoch}$extension';
            final tempPath = p.join(directory.path, fileName);
            final copiedFile = await sourceFile.copy(tempPath);
            await _prepareAudioFiles(copiedFile);
            return;
          } catch (e) {
            _setError('Failed to process file: $e');
            return;
          }
        }

        // For Android and other platforms, use the path directly
        final file = File(filePath);
        if (!file.existsSync()) {
          _setError(
            'Selected file does not exist. Please try selecting the file again.',
          );
          return;
        }

        await _prepareAudioFiles(file);
      }
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('multiple_request') ||
          errorMsg.contains('Cancelled') ||
          errorMsg.contains('cancel') ||
          errorMsg.contains('User canceled')) {
        // User cancelled, don't show error
        _isPickingFile = false;
        notifyListeners();
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
      if (_shouldUsePlatformPlayer) {
        final success = await PitchService.seek(position.inMilliseconds);
        if (success) {
          _iosPosition = position;
          notifyListeners();
        }
      } else {
        await _player.seek(position);
      }
    } catch (e) {
      _setError('Unable to seek: $e');
    }
  }

  Future<void> togglePlayback() async {
    if (!canPlay) return;
    try {
      if (_shouldUsePlatformPlayer) {
        if (_iosIsPlaying) {
          await PitchService.pause();
          _iosIsPlaying = false;
          _stopIOSPositionTimer();
        } else {
          await PitchService.play();
          _iosIsPlaying = true;
          _startIOSPositionTimer();
        }
      } else {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
      }
    } catch (e) {
      _setError('Playback failed: $e');
    }
    notifyListeners();
  }

  Future<void> stopPlayback() async {
    if (_shouldUsePlatformPlayer) {
      await PitchService.stop();
      _iosIsPlaying = false;
      _iosPosition = Duration.zero;
      _stopIOSPositionTimer();
    } else {
      await _player.stop();
    }
    notifyListeners();
  }

  Future<void> setDirection(PlaybackDirection direction) async {
    if (_direction == direction) return;

    // Stop playback before switching direction
    final wasPlaying = isPlaying;
    if (wasPlaying) {
      await stopPlayback();
    }

    _direction = direction;
    await _loadCurrentDirection();

    // Restart playback if it was playing before
    if (wasPlaying && canPlay) {
      await togglePlayback();
    }

    notifyListeners();
  }

  Future<void> setSpeed(double value) async {
    _speed = value;
    try {
      if (_shouldUsePlatformPlayer) {
        await PitchService.setSpeed(value);
      } else {
        await _player.setSpeed(value);
      }
    } catch (e) {
      _setError('Unable to set speed: $e');
    }
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    _pitch = value;
    try {
      if (_shouldUsePlatformPlayer) {
        await PitchService.setPitch(value);
      } else {
        await _player.setPitch(value);
      }
    } catch (e) {
      _setError('Unable to set pitch: $e');
    }
    notifyListeners();
  }

  Future<void> toggleLoop(bool enabled) async {
    _iosIsLooping = enabled;
    if (_shouldUsePlatformPlayer) {
      await PitchService.setLooping(enabled);
    } else {
      await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
    }
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

    // Verify file exists
    final file = File(path);
    if (!file.existsSync()) {
      _setError(
        'Audio file not found: ${_direction == PlaybackDirection.forward ? "forward" : "reverse"}',
      );
      return;
    }

    try {
      if (_shouldUsePlatformPlayer) {
        // Use platform channel player (iOS/Android)
        await PitchService.stop();
        _iosIsPlaying = false;
        _iosPosition = Duration.zero;
        _stopIOSPositionTimer();

        final success = await PitchService.loadAudio(path);
        if (success) {
          await PitchService.setSpeed(_speed);
          await PitchService.setPitch(_pitch);
          await PitchService.setLooping(_iosIsLooping);

          // Get duration
          final durationMs = await PitchService.getDuration();
          _iosDuration = Duration(milliseconds: durationMs);
        } else {
          _setError(
            'Failed to load audio on ${Platform.isIOS ? "iOS" : "Android"}',
          );
        }
      } else {
        // Use just_audio for web
        await _player.stop();
        await _player.setFilePath(path);
        await _player.setSpeed(_speed);
        await _player.setPitch(_pitch);
        await _player.setLoopMode(isLooping ? LoopMode.one : LoopMode.off);
      }
    } catch (e) {
      _setError('Failed to load audio: $e');
    }
  }

  void _startIOSPositionTimer() {
    _stopIOSPositionTimer();
    _iosPositionTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) async {
      if (!_iosIsPlaying) {
        timer.cancel();
        return;
      }
      try {
        final positionMs = await PitchService.getPosition();
        _iosPosition = Duration(milliseconds: positionMs);
        if (_iosDuration != null && _iosPosition >= _iosDuration!) {
          _iosPosition = _iosDuration!;
          if (!_iosIsLooping) {
            _iosIsPlaying = false;
            timer.cancel();
          }
        }
        notifyListeners();
      } catch (e) {
        // Ignore position errors
      }
    });
  }

  void _stopIOSPositionTimer() {
    _iosPositionTimer?.cancel();
    _iosPositionTimer = null;
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
    _stopIOSPositionTimer();
    if (_shouldUsePlatformPlayer) {
      PitchService.stop();
    } else {
      _player.dispose();
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
