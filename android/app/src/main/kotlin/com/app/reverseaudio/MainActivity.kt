package com.app.reverseaudio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val pitchHandler = PitchChannelHandler()
    private val reverseHandler = ReverseAudioHandler()
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the pitch channel handler
        val pitchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.reverseaudio.pitch")
        pitchChannel.setMethodCallHandler(pitchHandler)
        pitchHandler.setContext(applicationContext)
        
        // Register the reverse audio channel handler
        val reverseChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.reverseaudio.reverse")
        reverseChannel.setMethodCallHandler(reverseHandler)
    }
}
