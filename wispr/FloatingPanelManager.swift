import AppKit
import SwiftUI
import Combine

class FloatingPanelManager: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelManager()
    
    private var panel: NSPanel?
    
    @Published var status: AppStatus = .idle
    @Published var resultText: String = ""
    @Published var errorMessage: String = ""
    
    private override init() {
        super.init()
    }
    
    func setupPanel() {
        guard panel == nil else { return }
        
        let contentView = FloatingOverlayView(
            status: Binding(get: { self.status }, set: { self.status = $0 }),
            resultText: Binding(get: { self.resultText }, set: { self.resultText = $0 }),
            errorMessage: Binding(get: { self.errorMessage }, set: { self.errorMessage = $0 }),
            onRecordToggle: {
                Task { @MainActor in
                    if AudioRecorder.shared.isRecording {
                        WisprPipelineManager.shared.stopRecordingAndProcess()
                    } else {
                        WisprPipelineManager.shared.startRecording()
                    }
                }
            },
            onClose: {
                self.hidePanel()
            }
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        
        // FreeFlow exact RecordingOverlay.swift makeOverlayPanel implementation
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false
        newPanel.contentView = hostingView
        newPanel.delegate = self
        
        self.panel = newPanel
        centerPanelOnScreen()
    }
    
    func showPanel() {
        setupPanel()
        centerPanelOnScreen()
        panel?.orderFrontRegardless()
    }
    
    func hidePanel() {
        panel?.orderOut(nil)
    }
    
    func centerPanelOnScreen() {
        guard let mainScreen = NSScreen.main, let panel = panel else { return }
        let screenFrame = mainScreen.visibleFrame
        let panelSize = panel.frame.size
        
        let x = screenFrame.midX - (panelSize.width / 2.0)
        let y = screenFrame.maxY - panelSize.height - 40
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
