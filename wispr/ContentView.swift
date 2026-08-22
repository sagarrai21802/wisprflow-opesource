import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var pipeline = WisprPipelineManager.shared
    @ObservedObject var audioRecorder = AudioRecorder.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundColor(.purple)
                Text("Wispr Direct Audio Test Panel")
                    .font(.headline)
                Spacer()
            }
            
            // Record & Transcribe Controls
            HStack(spacing: 12) {
                Button(action: toggleRecord) {
                    HStack {
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                        Text(audioRecorder.isRecording ? "Stop Recording" : "Record Mic")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(audioRecorder.isRecording ? Color.red : Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                if let url = pipeline.recordedURL, !audioRecorder.isRecording {
                    Button(action: {
                        Task { await pipeline.processAudio(url: url) }
                    }) {
                        HStack {
                            if pipeline.isProcessing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send to Groq Whisper")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(pipeline.isProcessing ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(pipeline.isProcessing)
                }
                
                Spacer()
                
                Button("Clear Logs") {
                    pipeline.clearLogs()
                }
                .buttonStyle(.borderless)
            }
            
            // Live Wave Level Meter
            if audioRecorder.isRecording {
                HStack(spacing: 4) {
                    ForEach(0..<20) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: 4, height: max(6, CGFloat(audioRecorder.audioLevel) * 45.0 * CGFloat.random(in: 0.6...1.2)))
                    }
                }
                .frame(height: 50)
                .padding(.vertical, 4)
            }
            
            // Transcribed Text Result Box
            if !pipeline.transcribedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GROQ WHISPER RESPONSE:")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.green)
                    
                    Text("\"\(pipeline.transcribedText)\"")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
            }
            
            // Live Real-Time Logs Console
            VStack(alignment: .leading, spacing: 4) {
                Text("REAL-TIME EVENT LOGS:")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(pipeline.logs.enumerated()), id: \.offset) { index, log in
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(logColor(log))
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(6)
                    .onChange(of: pipeline.logs.count) { _ in
                        proxy.scrollTo(pipeline.logs.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onAppear {
            pipeline.setupPipeline()
        }
    }
    
    private func toggleRecord() {
        if audioRecorder.isRecording {
            pipeline.stopRecordingAndProcess()
        } else {
            pipeline.startRecording()
        }
    }
    
    private func logColor(_ log: String) -> Color {
        if log.contains("❌") { return .red }
        if log.contains("✅") || log.contains("🎉") || log.contains("🎯") { return .green }
        if log.contains("🔴") || log.contains("🛑") { return .yellow }
        return .primary
    }
}

#Preview {
    ContentView()
}
