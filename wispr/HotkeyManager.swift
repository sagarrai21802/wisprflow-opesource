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
    
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    /// Tracks if Right Option key is physically held down (FreeFlow ModifierKeyEventState parity)
    private(set) var isRightOptionDown = false
    
    // Right Option virtual keycode on macOS: 61 (0x3D)
    private let rightOptionKeyCode: UInt16 = 61
    
    private init() {}
    
    func startMonitoring() {
        stopMonitoring()
        
        // Attempt installing FreeFlow's exact CGEvent.tapCreate first
        installCGEventTap()
        
        // Always install NSEvent monitors as fallback for guaranteed hotkey detection
        installNSEventMonitors()
    }
    
    func stopMonitoring() {
        tearDownCGEventTap()
        removeNSEventMonitors()
    }
    
    // MARK: - FreeFlow CGEvent Tap (GlobalShortcutBackend.swift)
    
    private func installCGEventTap() {
        let eventMask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleCGEventTap(type: type, event: event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] ℹ️ CGEvent tap not available (will use NSEvent fallback).")
            return
        }
        
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        eventTap = tap
        eventTapRunLoopSource = source
        print("[HotkeyManager] ✅ FreeFlow CGEvent.tapCreate installed (headInsertEventTap, cgSessionEventTap).")
    }
    
    private func tearDownCGEventTap() {
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapRunLoopSource = nil
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
    }
    
    private func handleCGEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
            
        case .flagsChanged:
            guard let nsEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passUnretained(event)
            }
            processFlagsChanged(nsEvent)
            return Unmanaged.passUnretained(event)
            
        default:
            return Unmanaged.passUnretained(event)
        }
    }
    
    // MARK: - NSEvent Fallback Monitors
    
    private func installNSEventMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.processFlagsChanged(event)
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.processFlagsChanged(event)
            return event
        }
        print("[HotkeyManager] ✅ NSEvent monitors active for Right Option (keyCode 61).")
    }
    
    private func removeNSEventMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    // MARK: - Device-Level Right Option Evaluation (FreeFlow ModifierKeyEventState.swift)
    
    private func processFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == rightOptionKeyCode else { return }
        
        // FreeFlow exact device-level right option bitmask check (NX_DEVICERALTKEYMASK)
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
