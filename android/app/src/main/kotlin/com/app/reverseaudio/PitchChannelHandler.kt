package com.app.reverseaudio

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class PitchChannelHandler : MethodChannel.MethodCallHandler {
    private var exoPlayer: ExoPlayer? = null
    private var currentPitch: Float = 1.0f
    private var currentSpeed: Float = 1.0f
    private var isLooping: Boolean = false
    private var positionHandler: Handler? = null
    private var positionRunnable: Runnable? = null
    private var currentFilePath: String? = null
    private var context: Context? = null

    fun setContext(ctx: Context) {
        context = ctx
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setPitch" -> {
                val pitch = (call.arguments as? Map<*, *>)?.get("pitch") as? Double
                if (pitch != null) {
                    setPitch(pitch.toFloat(), result)
                } else {
                    result.success(false)
                }
            }
            "setSpeed" -> {
                val speed = (call.arguments as? Map<*, *>)?.get("speed") as? Double
                if (speed != null) {
                    setSpeed(speed.toFloat(), result)
                } else {
                    result.success(false)
                }
            }
            "loadAudio" -> {
                val filePath = (call.arguments as? Map<*, *>)?.get("filePath") as? String
                if (filePath != null) {
                    loadAudio(filePath, result)
                } else {
                    result.success(false)
                }
            }
            "play" -> play(result)
            "pause" -> pause(result)
            "stop" -> stop(result)
            "seek" -> {
                val position = (call.arguments as? Map<*, *>)?.get("position") as? Double
                if (position != null) {
                    seek(position.toLong(), result)
                } else {
                    result.success(false)
                }
            }
            "setLooping" -> {
                val looping = (call.arguments as? Map<*, *>)?.get("looping") as? Boolean
                if (looping != null) {
                    setLooping(looping, result)
                } else {
                    result.success(false)
                }
            }
            "getPosition" -> {
                val position = exoPlayer?.currentPosition ?: 0L
                result.success(position.toInt())
            }
            "getDuration" -> {
                val duration = exoPlayer?.duration ?: 0L
                result.success(if (duration == C.TIME_UNSET) 0 else duration.toInt())
            }
            "isPitchSupported" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    private fun setPitch(pitch: Float, result: MethodChannel.Result) {
        currentPitch = pitch.coerceIn(0.5f, 2.0f)
        
        exoPlayer?.let { player ->
            // ExoPlayer PlaybackParameters: pitch is a ratio (1.0 = no change, 2.0 = one octave up)
            // Constructor takes (speed, pitch) as positional parameters
            player.playbackParameters = PlaybackParameters(currentSpeed, currentPitch)
        }
        
        result.success(true)
    }

    private fun setSpeed(speed: Float, result: MethodChannel.Result) {
        currentSpeed = speed.coerceIn(0.25f, 4.0f)
        
        exoPlayer?.let { player ->
            // Constructor takes (speed, pitch) as positional parameters
            player.playbackParameters = PlaybackParameters(currentSpeed, currentPitch)
        }
        
        result.success(true)
    }
    
    private fun setPitchInternal(pitch: Float) {
        currentPitch = pitch.coerceIn(0.5f, 2.0f)
        exoPlayer?.let { player ->
            player.playbackParameters = PlaybackParameters(currentSpeed, currentPitch)
        }
    }
    
    private fun setSpeedInternal(speed: Float) {
        currentSpeed = speed.coerceIn(0.25f, 4.0f)
        exoPlayer?.let { player ->
            player.playbackParameters = PlaybackParameters(currentSpeed, currentPitch)
        }
    }

    private fun loadAudio(filePath: String, result: MethodChannel.Result) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                result.success(false)
                return
            }

            cleanup()

            val ctx = context ?: run {
                result.success(false)
                return
            }

            // Create ExoPlayer
            exoPlayer = ExoPlayer.Builder(ctx)
                .build()
                .apply {
                    val mediaItem = MediaItem.fromUri(android.net.Uri.fromFile(file))
                    setMediaItem(mediaItem)
                    prepare()
                    
                    addListener(object : Player.Listener {
                        override fun onPlaybackStateChanged(playbackState: Int) {
                            if (playbackState == Player.STATE_ENDED) {
                                if (isLooping) {
                                    seekTo(0)
                                    play()
                                } else {
                                    stopPositionUpdates()
                                }
                            }
                        }
                    })
                }

            currentFilePath = filePath
            
            // Apply current pitch and speed
            setPitchInternal(currentPitch)
            setSpeedInternal(currentSpeed)

            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("PitchChannelHandler", "Error loading audio: ${e.message}", e)
            result.success(false)
        }
    }

    private fun play(result: MethodChannel.Result) {
        exoPlayer?.let { player ->
            if (player.playbackState == Player.STATE_ENDED) {
                player.seekTo(0)
            }
            player.play()
            startPositionUpdates()
            result.success(true)
        } ?: result.success(false)
    }

    private fun pause(result: MethodChannel.Result) {
        exoPlayer?.pause()
        stopPositionUpdates()
        result.success(true)
    }

    private fun stop(result: MethodChannel.Result) {
        exoPlayer?.let { player ->
            player.stop()
            player.seekTo(0)
        }
        stopPositionUpdates()
        result.success(true)
    }

    private fun seek(position: Long, result: MethodChannel.Result) {
        exoPlayer?.let { player ->
            val duration = player.duration
            if (duration != C.TIME_UNSET && position >= 0 && position <= duration) {
                player.seekTo(position)
                result.success(true)
            } else {
                result.success(false)
            }
        } ?: result.success(false)
    }

    private fun setLooping(looping: Boolean, result: MethodChannel.Result) {
        isLooping = looping
        exoPlayer?.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
        result.success(true)
    }

    private fun startPositionUpdates() {
        stopPositionUpdates()
        positionHandler = Handler(Looper.getMainLooper())
        positionRunnable = object : Runnable {
            override fun run() {
                positionHandler?.postDelayed(this, 100)
            }
        }
        positionHandler?.post(positionRunnable!!)
    }

    private fun stopPositionUpdates() {
        positionRunnable?.let { positionHandler?.removeCallbacks(it) }
        positionRunnable = null
        positionHandler = null
    }

    private fun cleanup() {
        stopPositionUpdates()
        exoPlayer?.release()
        exoPlayer = null
        currentFilePath = null
    }
}

