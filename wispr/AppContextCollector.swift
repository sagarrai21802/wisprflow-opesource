import Foundation
import AppKit
import ApplicationServices

struct AppContextSnapshot {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    
    var summary: String {
        var parts: [String] = []
        if let appName = appName, !appName.isEmpty {
            parts.append("Active Application: \(appName)")
        }
        if let windowTitle = windowTitle, !windowTitle.isEmpty {
            parts.append("Window Title: \(windowTitle)")
        }
        if let selectedText = selectedText, !selectedText.isEmpty {
            parts.append("Selected/On-Screen Text Context: \"\(selectedText)\"")
        }
        return parts.joined(separator: "\n")
    }
}

final class AppContextCollector {
    static let shared = AppContextCollector()
    
    private init() {}
    
    /// Captures the current frontmost application, window title, and selected text/context
    func collectSnapshot() -> AppContextSnapshot {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppContextSnapshot(appName: nil, bundleIdentifier: nil, windowTitle: nil, selectedText: nil)
        }
        
        let appName = frontmostApp.localizedName
        let bundleIdentifier = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        let windowTitle = focusedWindowTitle(from: appElement) ?? appName
        let selectedText = activeSelectedText(from: appElement)
        
        print("[AppContextCollector] Captured App: \(appName ?? "Unknown"), Window: \(windowTitle ?? "None"), SelectedText: \(selectedText != nil ? "\(selectedText!.count) chars" : "None")")
        
        return AppContextSnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText
        )
    }
    
    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let focusedWindow = value else { return nil }
        
        let windowElement = focusedWindow as! AXUIElement
        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue)
        guard titleResult == .success, let title = titleValue as? String else { return nil }
        
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func activeSelectedText(from appElement: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let focusedElement = value else { return nil }
        
        let element = focusedElement as! AXUIElement
        var selectedTextValue: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        if textResult == .success, let selectedText = selectedTextValue as? String {
            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        
        // Fallback: Try reading value attribute if element is a text field / text area
        var valValue: CFTypeRef?
        let valResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valValue)
        if valResult == .success, let text = valValue as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Truncate fallback to max 500 chars to avoid prompt bloat
                return String(trimmed.prefix(500))
            }
        }
        
        return nil
    }
}
