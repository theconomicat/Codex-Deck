import AppKit
import ApplicationServices
import Carbon

/// Keep the native boundary small so the complete picker flow can be exercised
/// against a controlled tree, including delayed exposure and focus loss.
@MainActor
protocol AccessibilityClient {
    var foregroundPID: pid_t? { get }
    var shortcutKeysAreDown: Bool { get }
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef?
    func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError
    func press(_ element: AXUIElement) -> AXError
    func postKey(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t) throws
}

@MainActor
struct SystemAccessibilityClient: AccessibilityClient {
    var foregroundPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    var shortcutKeysAreDown: Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
        return !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
            || [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3].contains {
                CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
            }
    }

    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    func postKey(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t) throws {
        guard foregroundPID == pid else {
            throw NSError(domain: "CodexUsage.Keyboard", code: 2, userInfo: [NSLocalizedDescriptionKey: "The target app lost focus; no key was sent."])
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            throw NSError(domain: "CodexUsage.Keyboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create the model picker shortcut."])
        }
        down.flags = flags
        up.flags = flags
        // Process-directed events can bypass native shortcut routing. Post to
        // the foreground session, with explicit flags isolated from held keys.
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
