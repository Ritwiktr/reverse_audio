package com.app.reverseaudio

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class ReverseAudioHandler : MethodChannel.MethodCallHandler {
    private val TAG = "ReverseAudioHandler"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "reverseAudio" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                
                if (inputPath == null || outputPath == null) {
                    result.success(false)
                    return
                }
                
                // Run in background
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val success = reverseAudio(inputPath, outputPath)
                        withContext(Dispatchers.Main) {
                            result.success(success)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error reversing audio", e)
                        withContext(Dispatchers.Main) {
                            result.success(false)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun reverseAudio(inputPath: String, outputPath: String): Boolean {
        return try {
            val inputFile = File(inputPath)
            if (!inputFile.exists()) {
                Log.e(TAG, "Input file does not exist: $inputPath")
                return false
            }

            // Use simple WAV file reversal for better compatibility
            if (inputPath.endsWith(".wav", ignoreCase = true)) {
                reverseWavFile(inputPath, outputPath)
            } else {
                // For other formats, try to decode and reverse
                reverseUsingDecoder(inputPath, outputPath)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reversing audio: ${e.message}", e)
            false
        }
    }

    private fun reverseWavFile(inputPath: String, outputPath: String): Boolean {
        try {
            val inputStream = FileInputStream(inputPath)
            val header = ByteArray(44) // WAV header is 44 bytes
            inputStream.read(header)

            // Read all audio data
            val audioData = inputStream.readBytes()
            inputStream.close()

            // Get sample size from WAV header (bits per sample at offset 34)
            val bitsPerSample = ((header[35].toInt() and 0xFF) shl 8) or (header[34].toInt() and 0xFF)
            val bytesPerSample = bitsPerSample / 8
            
            // Get number of channels from WAV header (at offset 22)
            val numChannels = ((header[23].toInt() and 0xFF) shl 8) or (header[22].toInt() and 0xFF)
            val frameSize = bytesPerSample * numChannels

            // Reverse the audio data by frames
            val reversedData = ByteArray(audioData.size)
            val numFrames = audioData.size / frameSize

            for (i in 0 until numFrames) {
                val srcOffset = i * frameSize
                val dstOffset = (numFrames - 1 - i) * frameSize
                System.arraycopy(audioData, srcOffset, reversedData, dstOffset, frameSize)
            }

            // Write output file
            val outputStream = FileOutputStream(outputPath)
            outputStream.write(header)
            outputStream.write(reversedData)
            outputStream.close()

            Log.d(TAG, "Successfully reversed WAV file")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error reversing WAV file: ${e.message}", e)
            return false
        }
    }

    private fun reverseUsingDecoder(inputPath: String, outputPath: String): Boolean {
        var extractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        
        try {
            // Setup extractor
            extractor = MediaExtractor()
            extractor.setDataSource(inputPath)

            // Find audio track
            var audioTrackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val trackFormat = extractor.getTrackFormat(i)
                val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    format = trackFormat
                    break
                }
            }

            if (audioTrackIndex < 0 || format == null) {
                Log.e(TAG, "No audio track found")
                return false
            }

            extractor.selectTrack(audioTrackIndex)

            // Get audio properties
            val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: "audio/mp4a-latm"

            // Setup decoder
            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, null, null, 0)
            decoder.start()

            val bufferInfo = MediaCodec.BufferInfo()
            val decodedFrames = mutableListOf<ShortArray>()
            var isDecoding = true

            // Decode all audio
            while (isDecoding) {
                // Feed input
                val inputBufferIndex = decoder.dequeueInputBuffer(10000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                    val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                    
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    } else {
                        val presentationTimeUs = extractor.sampleTime
                        decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTimeUs, 0)
                        extractor.advance()
                    }
                }

                // Get output
                val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000)
                when {
                    outputBufferIndex >= 0 -> {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        if (outputBuffer != null && bufferInfo.size > 0) {
                            val pcmData = ShortArray(bufferInfo.size / 2)
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
                            outputBuffer.asShortBuffer().get(pcmData)
                            decodedFrames.add(pcmData)
                        }
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                    }
                    outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        Log.d(TAG, "Output format changed: ${decoder.outputFormat}")
                    }
                }

                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    isDecoding = false
                }
            }

            decoder.stop()
            decoder.release()
            extractor.release()

            if (decodedFrames.isEmpty()) {
                Log.e(TAG, "No audio frames decoded")
                return false
            }

            // Reverse the decoded frames
            val totalSamples = decodedFrames.sumOf { it.size }
            val reversedData = ShortArray(totalSamples)
            var writePos = totalSamples
            
            for (frame in decodedFrames) {
                writePos -= frame.size
                System.arraycopy(frame, 0, reversedData, writePos, frame.size)
            }

            // Write as WAV file for simplicity
            writeWavFile(outputPath, reversedData, sampleRate, channelCount)
            
            Log.d(TAG, "Successfully reversed audio using decoder")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error in reverseUsingDecoder: ${e.message}", e)
            return false
        } finally {
            decoder?.release()
            extractor?.release()
        }
    }

    private fun writeWavFile(path: String, samples: ShortArray, sampleRate: Int, channelCount: Int) {
        val outputStream = FileOutputStream(path)
        
        val bitsPerSample = 16
        val bytesPerSample = bitsPerSample / 8
        val dataSize = samples.size * bytesPerSample
        val fileSize = dataSize + 36

        // Write WAV header
        outputStream.write("RIFF".toByteArray())
        outputStream.write(intToBytes(fileSize))
        outputStream.write("WAVE".toByteArray())
        outputStream.write("fmt ".toByteArray())
        outputStream.write(intToBytes(16)) // fmt chunk size
        outputStream.write(shortToBytes(1)) // PCM format
        outputStream.write(shortToBytes(channelCount.toShort()))
        outputStream.write(intToBytes(sampleRate))
        outputStream.write(intToBytes(sampleRate * channelCount * bytesPerSample)) // byte rate
        outputStream.write(shortToBytes((channelCount * bytesPerSample).toShort())) // block align
        outputStream.write(shortToBytes(bitsPerSample.toShort()))
        outputStream.write("data".toByteArray())
        outputStream.write(intToBytes(dataSize))

        // Write audio data
        val buffer = ByteBuffer.allocate(samples.size * 2)
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        for (sample in samples) {
            buffer.putShort(sample)
        }
        outputStream.write(buffer.array())
        outputStream.close()
    }

    private fun intToBytes(value: Int): ByteArray {
        return byteArrayOf(
            (value and 0xFF).toByte(),
            ((value shr 8) and 0xFF).toByte(),
            ((value shr 16) and 0xFF).toByte(),
            ((value shr 24) and 0xFF).toByte()
        )
    }

    private fun shortToBytes(value: Short): ByteArray {
        return byteArrayOf(
            (value.toInt() and 0xFF).toByte(),
            ((value.toInt() shr 8) and 0xFF).toByte()
        )
    }
}


