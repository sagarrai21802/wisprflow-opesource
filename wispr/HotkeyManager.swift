import Foundation
import Cocoa
import AppKit

private extension NSEvent.ModifierFlags {
    static let rightOption = Self(rawValue: UInt(NX_DEVICERALTKEYMASK))
}

final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()
    
    // Callback handlers
    var onRightOptionPressed: (() -> Void)?
    var onRightOptionReleased: (() -> Void)?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    /// Tracks if Right Option key is physically held down
    private(set) var isRightOptionDown = false
    
    // Right Option virtual keycode on macOS: 61 (0x3D)
    private let rightOptionKeyCode: UInt16 = 61
    
    private init() {}
    
    func startMonitoring() {
        stopMonitoring()
        
        // Fast, zero-lag NSEvent monitors with instant keycode filter
        let handler: (NSEvent) -> Void = { [weak self] event in
            // Fast exit if NOT Right Option key (keyCode 61) to prevent any CPU/thread overhead
            guard event.keyCode == 61 else { return }
            self?.processFlagsChanged(event)
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if event.keyCode == 61 {
                self?.processFlagsChanged(event)
            }
            return event
        }
        
        print("[HotkeyManager] ⚡️ Lightweight zero-lag hotkey monitor active for Right Option (keyCode 61).")
    }
    
    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    private func processFlagsChanged(_ event: NSEvent) {
        let isDown = event.modifierFlags.contains(.rightOption) || event.modifierFlags.contains(.option)
        
        if isDown && !isRightOptionDown {
            isRightOptionDown = true
            print("[HotkeyManager] 🔴 Right Option Pressed!")
            DispatchQueue.main.async { [weak self] in
                self?.onRightOptionPressed?()
            }
        } else if !isDown && isRightOptionDown {
            isRightOptionDown = false
            print("[HotkeyManager] ⚪️ Right Option Released!")
            DispatchQueue.main.async { [weak self] in
                self?.onRightOptionReleased?()
            }
        }
    }
}
