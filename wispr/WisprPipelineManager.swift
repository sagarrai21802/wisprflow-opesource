import Foundation
import AppKit
import Combine

@MainActor
final class WisprPipelineManager: ObservableObject {
    static let shared = WisprPipelineManager()
    
    @Published var logs: [String] = []
    @Published var transcribedText: String = ""
    @Published var rawWhisperText: String = ""
    @Published var activeContext: AppContextSnapshot?
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
        
        // Capture Application Context asynchronously on background thread (zero main thread lag)
        Task.detached(priority: .userInitiated) {
            let snapshot = await AppContextCollector.shared.collectSnapshotAsync()
            await MainActor.run {
                WisprPipelineManager.shared.activeContext = snapshot
                if let app = snapshot.appName {
                    WisprPipelineManager.shared.addLog("📱 Active App Captured: \(app)\(snapshot.windowTitle != nil ? " (\(snapshot.windowTitle!))" : "")")
                }
            }
        }
        
        do {
            let url = try AudioRecorder.shared.startRecording()
            self.recordedURL = url
            self.transcribedText = ""
            self.rawWhisperText = ""
            addLog("🔴 Right Option / Button pressed -> Recording started... Speak now!")
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
        
        // Process Pipeline: Groq STT -> Gemini Contextual AI -> Caret Paste
        Task {
            await processAudioPipeline(url: fileURL)
        }
    }
    
    func processAudioPipeline(url: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        addLog("🛫 Step 1: Transcribing audio via Groq Whisper API (\(fileSize / 1024) KB)...")
        
        let startTime = Date()
        
        do {
            // Step 1: Sub-Second Speech-To-Text via Groq Whisper (whisper-large-v3)
            let rawWhisperResult = try await GroqService.shared.transcribeAudio(fileURL: url)
            let groqDuration = String(format: "%.2f", Date().timeIntervalSince(startTime))
            
            guard !rawWhisperResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                addLog("⚠️ Groq returned EMPTY transcript (filtered silence/noise).")
                self.transcribedText = "[No Speech Detected]"
                self.isProcessing = false
                return
            }
            
            self.rawWhisperText = rawWhisperResult
            addLog("🎉 ✅ Groq Whisper STT in \(groqDuration)s: \"\(rawWhisperResult)\"")
            
            // Step 2: Context-Aware Intelligence via Gemini AI (gemini-2.5-flash)
            let geminiStartTime = Date()
            let snapshot = self.activeContext ?? AppContextCollector.shared.collectSnapshot()
            addLog("✨ Step 2: Processing transcript + App Context (\(snapshot.appName ?? "General")) via Gemini AI...")
            
            let finalGeneratedText = try await GeminiService.shared.processWithContext(
                rawTranscript: rawWhisperResult,
                context: snapshot
            )
            
            let geminiDuration = String(format: "%.2f", Date().timeIntervalSince(geminiStartTime))
            addLog("🤖 ✅ Gemini AI Generated in \(geminiDuration)s:")
            addLog("📝 Output: \"\(finalGeneratedText)\"")
            
            self.transcribedText = finalGeneratedText
            
            // Step 3: Direct Caret Pasting via Command+V Keystroke Injection
            addLog("🎯 Step 3: Pasting generated text directly at active cursor via Cmd+V...")
            CaretManager.shared.pasteTextAtCaret(finalGeneratedText)
            addLog("✅ Pasted at cursor location!")
            
        } catch {
            let totalDuration = String(format: "%.2f", Date().timeIntervalSince(startTime))
            addLog("❌ ERROR after \(totalDuration)s: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    func clearLogs() {
        logs.removeAll()
        transcribedText = ""
        rawWhisperText = ""
        activeContext = nil
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
