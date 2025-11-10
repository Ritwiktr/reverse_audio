import Flutter
import UIKit
import AVFoundation

class PitchChannelHandler: NSObject, FlutterPlugin {
    private var channelName: String?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        // Register pitch channel
        let pitchChannel = FlutterMethodChannel(name: "com.reverseaudio.pitch", binaryMessenger: registrar.messenger())
        let pitchInstance = PitchChannelHandler()
        pitchInstance.channelName = "com.reverseaudio.pitch"
        pitchChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            pitchInstance.handle(call, result: result)
        }
        
        // Register reverse channel
        let reverseChannel = FlutterMethodChannel(name: "com.reverseaudio.reverse", binaryMessenger: registrar.messenger())
        let reverseInstance = PitchChannelHandler()
        reverseInstance.channelName = "com.reverseaudio.reverse"
        reverseChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            reverseInstance.handle(call, result: result)
        }
        
        print("PitchChannelHandler: Registered pitch and reverse audio channels")
    }
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var pitchNode: AVAudioUnitTimePitch?
    private var audioFile: AVAudioFile?
    private var currentPitch: Float = 1.0
    private var currentSpeed: Float = 1.0
    private var isPlaying: Bool = false
    private var isLooping: Bool = false
    private var currentPosition: TimeInterval = 0.0
    private var fileDuration: TimeInterval = 0.0
    private var positionTimer: Timer?
    private var eventSink: FlutterEventSink?
    private var eventChannel: FlutterEventChannel?
    
    override init() {
        super.init()
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let currentChannel = channelName ?? "unknown"
        print("PitchChannelHandler: Received method call: \(call.method) on channel: \(currentChannel)")
        
        // Handle reverse audio channel methods
        if currentChannel == "com.reverseaudio.reverse" {
            if call.method == "reverseAudio" {
                print("PitchChannelHandler: Processing reverseAudio request")
                guard let args = call.arguments as? [String: Any],
                      let inputPath = args["inputPath"] as? String,
                      let outputPath = args["outputPath"] as? String else {
                    print("PitchChannelHandler: Invalid arguments for reverseAudio")
                    result(false)
                    return
                }
                print("PitchChannelHandler: Reversing audio from \(inputPath) to \(outputPath)")
                reverseAudio(inputPath: inputPath, outputPath: outputPath, result: result)
                return
            } else {
                print("PitchChannelHandler: Unknown method \(call.method) on reverse channel")
                result(FlutterMethodNotImplemented)
                return
            }
        }
        
        // Handle pitch channel methods (com.reverseaudio.pitch)
        if currentChannel != "com.reverseaudio.pitch" {
            print("PitchChannelHandler: Warning - method \(call.method) called on unexpected channel: \(currentChannel)")
        }
        
        switch call.method {
        case "setPitch":
            guard let args = call.arguments as? [String: Any],
                  let pitch = args["pitch"] as? Double else {
                result(false)
                return
            }
            setPitch(pitch: Float(pitch), result: result)
            
        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double else {
                result(false)
                return
            }
            setSpeed(speed: Float(speed), result: result)
            
        case "loadAudio":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String else {
                result(false)
                return
            }
            loadAudio(filePath: filePath, result: result)
            
        case "play":
            play(result: result)
            
        case "pause":
            pause(result: result)
            
        case "stop":
            stop(result: result)
            
        case "seek":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Double else {
                result(false)
                return
            }
            seek(to: position, result: result)
            
        case "setLooping":
            guard let args = call.arguments as? [String: Any],
                  let looping = args["looping"] as? Bool else {
                result(false)
                return
            }
            setLooping(looping: looping, result: result)
            
        case "getPosition":
            result(Int(currentPosition * 1000)) // Return in milliseconds as Int
            
        case "getDuration":
            result(Int(fileDuration * 1000)) // Return in milliseconds as Int
            
        case "isPitchSupported":
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func setPitch(pitch: Float, result: @escaping FlutterResult) {
        currentPitch = pitch
        
        if let pitchNode = pitchNode {
            // Convert pitch ratio to cents
            // 1.0 = 0 cents, 2.0 = 1200 cents (one octave up)
            // AVAudioUnitTimePitch uses cents: -2400 to +2400
            let pitchInCents = (pitch - 1.0) * 1200.0
            pitchNode.pitch = max(-2400, min(2400, pitchInCents))
        }
        result(true)
    }
    
    private func setSpeed(speed: Float, result: @escaping FlutterResult) {
        currentSpeed = speed
        
        if let pitchNode = pitchNode {
            // AVAudioUnitTimePitch rate: 0.25 to 4.0
            pitchNode.rate = max(0.25, min(4.0, speed))
        }
        result(true)
    }
    
    private func loadAudio(filePath: String, result: @escaping FlutterResult) {
        do {
            let fileURL = URL(fileURLWithPath: filePath)
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: filePath) else {
                print("PitchChannelHandler: File does not exist at path: \(filePath)")
                result(false)
                return
            }
            
            // Clean up existing engine if any
            cleanup()
            
            // Initialize audio engine
            audioEngine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            pitchNode = AVAudioUnitTimePitch()
            
            guard let engine = audioEngine,
                  let player = playerNode,
                  let pitch = pitchNode else {
                print("PitchChannelHandler: Failed to initialize audio components")
                result(false)
                return
            }
            
            // Load audio file
            audioFile = try AVAudioFile(forReading: fileURL)
            guard let file = audioFile else {
                print("PitchChannelHandler: Failed to load audio file")
                result(false)
                return
            }
            
            print("PitchChannelHandler: Successfully loaded audio file: \(filePath)")
            
            // Get file duration
            fileDuration = Double(file.length) / file.fileFormat.sampleRate
            
            // Configure pitch node
            let pitchInCents = (currentPitch - 1.0) * 1200.0
            pitch.pitch = max(-2400, min(2400, pitchInCents))
            pitch.rate = max(0.25, min(4.0, currentSpeed))
            
            // Attach nodes to engine
            engine.attach(player)
            engine.attach(pitch)
            
            // Connect: player -> pitch -> output
            engine.connect(player, to: pitch, format: file.processingFormat)
            engine.connect(pitch, to: engine.mainMixerNode, format: nil)
            
            // Start engine
            try engine.start()
            
            // Reset position
            currentPosition = 0.0
            
            result(true)
        } catch {
            print("PitchChannelHandler: Error loading audio: \(error.localizedDescription)")
            result(false)
        }
    }
    
    private func play(result: @escaping FlutterResult) {
        guard let player = playerNode,
              let file = audioFile else {
            result(false)
            return
        }
        
        if !isPlaying {
            if currentPosition >= fileDuration {
                currentPosition = 0.0
            }
            
            // Calculate frame position
            let sampleRate = file.fileFormat.sampleRate
            let startFrame = AVAudioFramePosition(currentPosition * sampleRate)
            
            // Schedule playback
            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(file.length - startFrame),
                at: nil
            ) { [weak self] in
                DispatchQueue.main.async {
                    self?.playbackFinished()
                }
            }
            
            player.play()
            isPlaying = true
            startPositionTimer()
            result(true)
        } else {
            result(true)
        }
    }
    
    private func pause(result: @escaping FlutterResult) {
        playerNode?.pause()
        isPlaying = false
        stopPositionTimer()
        result(true)
    }
    
    private func stop(result: @escaping FlutterResult) {
        playerNode?.stop()
        isPlaying = false
        currentPosition = 0.0
        stopPositionTimer()
        result(true)
    }
    
    private func seek(to position: Double, result: @escaping FlutterResult) {
        let wasPlaying = isPlaying
        let seekPosition = position / 1000.0 // Convert from milliseconds
        
        if seekPosition < 0 || seekPosition > fileDuration {
            result(false)
            return
        }
        
        currentPosition = seekPosition
        
        // Stop current playback
        playerNode?.stop()
        stopPositionTimer()
        isPlaying = false
        
        if wasPlaying {
            // Restart from new position
            guard let player = playerNode,
                  let file = audioFile else {
                result(false)
                return
            }
            
            // Calculate frame position
            let sampleRate = file.fileFormat.sampleRate
            let startFrame = AVAudioFramePosition(seekPosition * sampleRate)
            
            // Schedule playback from new position
            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(file.length - startFrame),
                at: nil
            ) { [weak self] in
                DispatchQueue.main.async {
                    self?.playbackFinished()
                }
            }
            
            player.play()
            isPlaying = true
            startPositionTimer()
        }
        
        result(true)
    }
    
    private func setLooping(looping: Bool, result: @escaping FlutterResult) {
        isLooping = looping
        result(true)
    }
    
    private func playbackFinished() {
        if isLooping {
            currentPosition = 0.0
            play(result: { _ in })
        } else {
            isPlaying = false
            currentPosition = fileDuration
            stopPositionTimer()
        }
    }
    
    private func startPositionTimer() {
        stopPositionTimer()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.currentPosition += 0.1 * Double(self.currentSpeed)
            if self.currentPosition > self.fileDuration {
                self.currentPosition = self.fileDuration
            }
        }
    }
    
    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }
    
    private func cleanup() {
        stopPositionTimer()
        audioEngine?.stop()
        playerNode?.stop()
        audioEngine = nil
        playerNode = nil
        pitchNode = nil
        audioFile = nil
        isPlaying = false
        currentPosition = 0.0
    }
    
    // Reverse audio file
    private func reverseAudio(inputPath: String, outputPath: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let inputURL = URL(fileURLWithPath: inputPath)
                let outputURL = URL(fileURLWithPath: outputPath)
                
                // Load the audio file
                let audioFile = try AVAudioFile(forReading: inputURL)
                let format = audioFile.processingFormat
                let frameCount = AVAudioFrameCount(audioFile.length)
                
                // Read all audio data
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    DispatchQueue.main.async {
                        result(false)
                    }
                    return
                }
                
                try audioFile.read(into: buffer)
                
                // Reverse the audio buffer
                if let channelData = buffer.floatChannelData {
                    let channelCount = Int(format.channelCount)
                    let frameLength = Int(buffer.frameLength)
                    
                    for channel in 0..<channelCount {
                        let channelBuffer = channelData[channel]
                        // Reverse the channel data
                        for i in 0..<(frameLength / 2) {
                            let swapIndex = frameLength - 1 - i
                            let temp = channelBuffer[i]
                            channelBuffer[i] = channelBuffer[swapIndex]
                            channelBuffer[swapIndex] = temp
                        }
                    }
                } else if let channelData = buffer.int16ChannelData {
                    let channelCount = Int(format.channelCount)
                    let frameLength = Int(buffer.frameLength)
                    
                    for channel in 0..<channelCount {
                        let channelBuffer = channelData[channel]
                        // Reverse the channel data
                        for i in 0..<(frameLength / 2) {
                            let swapIndex = frameLength - 1 - i
                            let temp = channelBuffer[i]
                            channelBuffer[i] = channelBuffer[swapIndex]
                            channelBuffer[swapIndex] = temp
                        }
                    }
                } else if let channelData = buffer.int32ChannelData {
                    let channelCount = Int(format.channelCount)
                    let frameLength = Int(buffer.frameLength)
                    
                    for channel in 0..<channelCount {
                        let channelBuffer = channelData[channel]
                        // Reverse the channel data
                        for i in 0..<(frameLength / 2) {
                            let swapIndex = frameLength - 1 - i
                            let temp = channelBuffer[i]
                            channelBuffer[i] = channelBuffer[swapIndex]
                            channelBuffer[swapIndex] = temp
                        }
                    }
                }
                
                // Create output file
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                
                // Write reversed buffer to output file
                try outputFile.write(from: buffer)
                
                DispatchQueue.main.async {
                    result(true)
                }
            } catch {
                print("PitchChannelHandler: Error reversing audio: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    result(false)
                }
            }
        }
    }
}
