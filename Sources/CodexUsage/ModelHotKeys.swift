import AppKit
import Carbon

/// Register only while Codex is foreground, so other apps retain these keys.
@MainActor
final class ModelHotKeys: NSObject {
    static let codexBundleID = "com.openai.codex"
    var onSelect: ((Int) -> Void)?
    var onError: ((String) -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    private var pressedSlots: Set<Int> = []

    // Injectable only for the native keyboard test host; production uses Codex.
    private let targetBundleID: String

    init(targetBundleID: String = ModelHotKeys.codexBundleID) {
        self.targetBundleID = targetBundleID
        super.init()
    }

    func start() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let result = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            guard id.signature == 0x43555850, (1...5).contains(id.id) else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<ModelHotKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                let slot = Int(id.id)
                if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                    owner.pressedSlots.insert(slot)
                } else if owner.pressedSlots.remove(slot) != nil {
                    owner.onSelect?(slot)
                }
            }
            // Consume both edges; an unhandled press can reach the foreground
            // app's number shortcuts before the release callback runs.
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else {
            onError?("Could not install shortcut handler (\(result)).")
            return
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateRegistration),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        updateRegistration()
    }

    @objc private func updateRegistration() {
        keys.forEach { UnregisterEventHotKey($0) }
        keys.removeAll()
        pressedSlots.removeAll()
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleID else { return }
        for (index, code) in [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x43555850, id: UInt32(index + 1))
            let status = RegisterEventHotKey(UInt32(code), UInt32(cmdKey | controlKey), id,
                                            GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if status == noErr, let reference {
                keys.append(reference)
            } else {
                onError?("⌘⌃\(index + 1) could not be registered (\(status)); another app may be using it.")
            }
        }
    }

    func stop() {
        keys.forEach { UnregisterEventHotKey($0) }
        keys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
