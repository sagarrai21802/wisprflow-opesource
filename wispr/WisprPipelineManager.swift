import Foundation
import AppKit
import Combine

@MainActor
final class WisprPipelineManager: ObservableObject {
    static let shared = WisprPipelineManager()
    
    @Published var logs: [String] = []
    @Published var transcribedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var recordedURL: URL?
    
    private init() {}
    
    func setupPipeline() {
        print("[WisprPipeline] Initializing pipeline...")
        _ = Config.shared
        
        let hasAccess = CaretManager.shared.isAccessibilityPermissionGranted()
        if !hasAccess {
            addLog("⚠️ Accessibility permission missing in TCC cache. Polling in background...")
            CaretManager.shared.startAccessibilityPolling()
        } else {
            addLog("System initialized. Accessibility permission: ✅ Granted")
        }
        addLog("Hotkey ready: Press & hold 'Right Option' key anywhere on your Mac to dictate!")
        
        Task {
            _ = await AudioRecorder.shared.requestPermission()
        }
        
        // Setup Global Hotkey Callbacks (Right Option Press / Release)
        HotkeyManager.shared.onRightOptionPressed = { [weak self] in
            Task { @MainActor in
                self?.handleRightOptionPressed()
            }
        }
        
        HotkeyManager.shared.onRightOptionReleased = { [weak self] in
            Task { @MainActor in
                self?.handleRightOptionReleased()
            }
        }
        
        HotkeyManager.shared.startMonitoring()
    }
    
    func startRecording() {
        guard !AudioRecorder.shared.isRecording && !isProcessing else { return }
        do {
            let url = try AudioRecorder.shared.startRecording()
            self.recordedURL = url
            self.transcribedText = ""
            addLog("🔴 Right Option / Button pressed -> Recording started via AVCaptureSession... Speak now!")
        } catch {
            addLog("❌ Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecordingAndProcess() {
        guard AudioRecorder.shared.isRecording else { return }
        
        guard let fileURL = AudioRecorder.shared.stopRecording() else {
            addLog("⚠️ No audio recorded.")
            return
        }
        
        self.recordedURL = fileURL
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        addLog("🛑 Recording stopped. WAV file size: \(fileSize) bytes (\(fileSize / 1024) KB)")
        addLog("💾 Saved debug audio copy to /Users/apple/Desktop/new/wispr/debug_recording.wav")
        
        // Automatically send to Groq Whisper and paste at cursor
        Task {
            await processAudio(url: fileURL)
        }
    }
    
    func processAudio(url: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        addLog("🛫 Sending HTTP POST to Groq Whisper API (\(fileSize) bytes)...")
        
        let startTime = Date()
        
        do {
            let result = try await GroqService.shared.transcribeAudio(fileURL: url)
            let duration = String(format: "%.2f", Date().timeIntervalSince(startTime))
            
            if result.isEmpty {
                addLog("⚠️ Groq returned EMPTY transcript (filtered silence/noise).")
                self.transcribedText = "[No Speech Detected]"
            } else {
                addLog("🎉 ✅ SUCCESS in \(duration)s!")
                addLog("📝 Output: \"\(result)\"")
                self.transcribedText = result
                
                // Auto-paste text directly at active cursor (FreeFlow exact behavior)
                addLog("🎯 Pasting text directly at active cursor via Cmd+V...")
                CaretManager.shared.pasteTextAtCaret(result)
                addLog("✅ Pasted at cursor location!")
            }
        } catch {
            let duration = String(format: "%.2f", Date().timeIntervalSince(startTime))
            addLog("❌ ERROR after \(duration)s: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    func clearLogs() {
        logs.removeAll()
        transcribedText = ""
    }
    
    private func handleRightOptionPressed() {
        startRecording()
    }
    
    private func handleRightOptionReleased() {
        stopRecordingAndProcess()
    }
    
    private func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
    }
}
