import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PitchService {
  static const MethodChannel _channel = MethodChannel('com.reverseaudio.pitch');

  /// Sets the pitch for the audio player
  /// Returns true if successful, false otherwise
  static Future<bool> setPitch(double pitch) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('setPitch', {
        'pitch': pitch,
      });
      return result ?? false;
    } catch (e) {
      // Silently fail - pitch might not be fully implemented yet
      debugPrint('PitchService: Error setting pitch: $e');
      return false;
    }
  }

  /// Sets the speed for the audio player
  static Future<bool> setSpeed(double speed) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('setSpeed', {
        'speed': speed,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('PitchService: Error setting speed: $e');
      return false;
    }
  }

  /// Loads audio file for playback
  static Future<bool> loadAudio(String filePath) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('loadAudio', {
        'filePath': filePath,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('PitchService: Error loading audio: $e');
      return false;
    }
  }

  /// Plays audio
  static Future<bool> play() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('play');
      return result ?? false;
    } catch (e) {
      debugPrint('PitchService: Error playing audio: $e');
      return false;
    }
  }

  /// Pauses audio playback
  static Future<bool> pause() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('pause');
      return result ?? false;
    } catch (e) {
      debugPrint('PitchService: Error pausing audio: $e');
      return false;
    }
  }

  /// Stops audio playback
  static Future<bool> stop() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('stop');
      return result ?? false;
    } catch (e) {
      debugPrint('PitchService: Error stopping audio: $e');
      return false;
    }
  }

  /// Seeks to a specific position in milliseconds
  static Future<bool> seek(int positionMs) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('seek', {
        'position': positionMs.toDouble(),
      });
      return result ?? false;
    } catch (e) {
      debugPrint('PitchService: Error seeking: $e');
      return false;
    }
  }

  /// Sets looping mode
  static Future<bool> setLooping(bool looping) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('setLooping', {
        'looping': looping,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('PitchService: Error setting looping: $e');
      return false;
    }
  }

  /// Gets current playback position in milliseconds
  static Future<int> getPosition() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return 0;
    }

    try {
      final result = await _channel.invokeMethod('getPosition');
      if (result is int) {
        return result;
      } else if (result is double) {
        return result.toInt();
      }
      return 0;
    } catch (e) {
      debugPrint('PitchService: Error getting position: $e');
      return 0;
    }
  }

  /// Gets audio duration in milliseconds
  static Future<int> getDuration() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return 0;
    }

    try {
      final result = await _channel.invokeMethod('getDuration');
      if (result is int) {
        return result;
      } else if (result is double) {
        return result.toInt();
      }
      return 0;
    } catch (e) {
      debugPrint('PitchService: Error getting duration: $e');
      return 0;
    }
  }

  /// Checks if pitch control is available on this platform
  static Future<bool> isPitchSupported() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isPitchSupported');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
