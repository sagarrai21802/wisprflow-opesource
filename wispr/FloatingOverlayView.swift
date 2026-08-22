import SwiftUI
import AppKit

enum AppStatus: String {
    case idle = "Press Right Option to Dictate"
    case recording = "Listening... Speak now"
    case uploading = "Transcribing via Groq Whisper..."
    case transcribing = "Transcribing speech..."
    case refining = "Formatting with Gemini AI..."
    case autoPasted = "Pasted text at cursor! ✅"
    case readyForCopy = "Text Ready"
    case error = "Error"
}

struct FloatingOverlayView: View {
    @ObservedObject var audioRecorder = AudioRecorder.shared
    
    @Binding var status: AppStatus
    @Binding var resultText: String
    @Binding var errorMessage: String
    
    var onRecordToggle: () -> Void
    var onClose: () -> Void
    
    @State private var isCopied = false
    
    var body: some View {
        VStack(spacing: 14) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    
                    Text("WISPR VOICE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Central Content Area
            if status == .recording {
                VStack(spacing: 12) {
                    // Live Audio Wave Level Meter
                    HStack(spacing: 4) {
                        ForEach(0..<12) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(LinearGradient(gradient: Gradient(colors: [.purple, .blue]), startPoint: .bottom, endPoint: .top))
                                .frame(width: 4, height: max(6, CGFloat(audioRecorder.audioLevel) * 40.0 * CGFloat.random(in: 0.5...1.2)))
                                .animation(.easeOut(duration: 0.1), value: audioRecorder.audioLevel)
                        }
                    }
                    .frame(height: 45)
                    
                    Text(status.rawValue)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 8)
            } else if status == .uploading || status == .transcribing || status == .refining {
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                    
                    Text(status.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
            } else if !resultText.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(resultText)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                    
                    HStack {
                        if status == .autoPasted {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Auto-pasted into text area")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("\(resultText.count) characters")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: copyToClipboard) {
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "Copied!" : "Copy")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isCopied ? Color.green : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Press **Right Option** key anywhere to record audio, transcribe via AssemblyAI, & refine via Gemini.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(action: onRecordToggle) {
                        HStack {
                            Image(systemName: "mic.fill")
                            Text("Start Recording")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        switch status {
        case .recording: return .red
        case .uploading, .transcribing, .refining: return .orange
        case .autoPasted, .readyForCopy: return .green
        case .error: return .red
        case .idle: return .blue
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
