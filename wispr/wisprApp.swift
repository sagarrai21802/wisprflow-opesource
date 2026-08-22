import SwiftUI

@main
struct wisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // FreeFlow exact activation policy: run as background accessory app
        // so window NEVER steals keyboard focus from active text editors!
        NSApp.setActivationPolicy(.accessory)
        
        // Setup menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Wispr Voice Dictation")
            button.action = #selector(menuBarClicked)
            button.target = self
        }
        
        WisprPipelineManager.shared.setupPipeline()
    }
    
    @objc func menuBarClicked() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
