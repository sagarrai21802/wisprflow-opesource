import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = AudioRecorder()
    
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioFile: AVAudioFile?
    private var audioConverter: AVAudioConverter?
    private var tempAudioURL: URL?
    private var lastSavedWorkspaceURL: URL?
    
    private let sampleQueue = DispatchQueue(label: "com.wispr.capture.samples")
    
    // FreeFlow target format: 16 kHz Mono 16-bit Int PCM WAV
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!
    
    private override init() {
        super.init()
    }
    
    /// Requests microphone recording permission from macOS
    func requestPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            print("[AudioRecorder] Mic permission (macOS 14+): \(granted)")
            return granted
        } else {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    print("[AudioRecorder] Mic permission (legacy): \(granted)")
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// Starts recording audio using AVCaptureSession matching FreeFlow
    func startRecording() throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("wispr_dictation_\(Int(Date().timeIntervalSince1970)).wav")
        
        let workspaceURL = URL(fileURLWithPath: "/Users/apple/Desktop/new/wispr/debug_recording.wav")
        self.lastSavedWorkspaceURL = workspaceURL
        self.tempAudioURL = fileURL
        self.audioConverter = nil
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        guard let micDevice = AVCaptureDevice.default(for: .audio) ?? AVCaptureDevice.default(.microphone, for: .audio, position: .unspecified) else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone device found on Mac"])
        }
        
        print("[AudioRecorder] Using microphone device: \(micDevice.localizedName) (ID: \(micDevice.uniqueID))")
        
        let input = try AVCaptureDeviceInput(device: micDevice)
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add mic input to session"])
        }
        
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        session.commitConfiguration()
        session.startRunning()
        
        self.captureSession = session
        self.audioOutput = output
        self.isRecording = true
        
        print("[AudioRecorder] Recording started (FreeFlow 16kHz WAV format) -> \(fileURL.path)")
        return fileURL
    }
    
    /// Stops recording audio, writes WAV file, and copies to workspace debug_recording.wav
    func stopRecording() -> URL? {
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        audioFile = nil
        audioConverter = nil
        isRecording = false
        audioLevel = 0.0
        
        guard let fileURL = tempAudioURL else { return nil }
        tempAudioURL = nil
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        print("[AudioRecorder] Recording stopped. Temporary 16kHz WAV size: \(fileSize) bytes")
        
        if let workspaceURL = lastSavedWorkspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
            do {
                try FileManager.default.copyItem(at: fileURL, to: workspaceURL)
                print("[AudioRecorder] 💾 Saved copy of recorded audio to: \(workspaceURL.path) (\(fileSize) bytes)")
            } catch {
                print("[AudioRecorder] Failed to copy debug recording: \(error)")
            }
        }
        
        return fileURL
    }
}

extension AudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return }
        
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return }
        inputBuffer.frameLength = frameCount
        
        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: inputBuffer.mutableAudioBufferList
        )
        guard copyStatus == noErr else { return }
        
        // Calculate audio power level for waveform UI
        var rms: Float = 0
        if let floatData = inputBuffer.floatChannelData {
            var sum: Float = 0
            let step = max(1, Int(frameCount) / 50)
            for i in stride(from: 0, to: Int(frameCount), by: step) {
                let sample = floatData[0][i]
                sum += sample * sample
            }
            rms = sqrt(sum / Float(max(1, Int(frameCount) / step)))
        }
        let level = min(1.0, max(0.0, rms * 5.0))
        
        Task { @MainActor in
            self.audioLevel = level
            
            // Create audio file on first frame using FreeFlow's exact 16kHz Int16 Mono WAV format
            if self.audioFile == nil, let url = self.tempAudioURL {
                let pcmSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                self.audioFile = try? AVAudioFile(forWriting: url, settings: pcmSettings, commonFormat: .pcmFormatInt16, interleaved: true)
                self.audioConverter = AVAudioConverter(from: sourceFormat, to: self.targetFormat)
                print("[AudioRecorder] Created 16kHz Mono WAV writer (FreeFlow specs)")
            }
            
            if sourceFormat == self.targetFormat {
                try? self.audioFile?.write(from: inputBuffer)
            } else if let converter = self.audioConverter {
                let ratio = 16000.0 / sourceFormat.sampleRate
                let capacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 32
                if let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) {
                    var inputSupplied = false
                    let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
                        if inputSupplied {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        inputSupplied = true
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }
                    if status != .error && outputBuffer.frameLength > 0 {
                        try? self.audioFile?.write(from: outputBuffer)
                    }
                }
            }
        }
    }
}
