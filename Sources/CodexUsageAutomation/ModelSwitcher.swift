import AppKit
import ApplicationServices
import Carbon
import CodexUsageCore

@MainActor
public final class ModelSwitcher {
    private var busy = false
    public init() {}

    public func apply(_ preset: ModelPreset) async throws {
        guard !busy else { throw SwitchError.message("A model change is already in progress.") }
        guard AXIsProcessTrusted() else {
            throw SwitchError.message("Enable Codex Deck in System Settings → Privacy & Security → Accessibility, then retry.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.openai.codex" else {
            throw SwitchError.message("Open the Codex chat you want to change, then press its shortcut.")
        }
        busy = true
        defer { busy = false }
        let picker = AccessiblePicker(pid: app.processIdentifier)
        try await picker.apply(preset)
    }
}

extension AccessiblePicker {
    func apply(_ preset: ModelPreset) async throws {
        try await prepare()
        try await waitForShortcutRelease()
        let picker = self
        // A retry may start with the previous picker still open.
        let before = try picker.controls().filter { !$0.inPicker }
        // Prefer the actual composer button; use the documented shortcut only
        // when the UI has not exposed a uniquely named trigger.
        try picker.open(using: before)
        // Current Codex first opens a compact Power view. Its "Select model"
        // action reveals the actual model list; the list is initially inert.
        let entry = try await picker.waitForControl(excluding: before, stage: "Open model list", retryOpen: true) { labels in
            labels.contains { PickerLabels.isModelListOpener($0) || PickerLabels.model($0, matches: preset.model) }
        }
        let model: AccessibleControl
        if entry.labels.contains(where: PickerLabels.isModelListOpener) {
            try await picker.activateMenuItem(entry)
            model = try await picker.waitForControl(excluding: before, stage: "Find \(preset.model)") { labels in
                labels.contains { PickerLabels.model($0, matches: preset.model) }
            }
        } else {
            model = entry
        }
        try await picker.activateMenuItem(model)

        do {
            // Selecting a model returns to Power, restricted to that model's
            // supported efforts. Read the current selection after every arrow.
            try await picker.adjustPower(to: preset, excluding: before)
            try picker.dismiss()
            try await Task.sleep(for: .milliseconds(150))
            if try picker.isCombinedSelection(preset, among: before) { return }
            // Some trigger buttons expose only "Select model". Reopen and
            // confirm the persisted Power value instead of assuming AXPress worked.
            try picker.open()
            let effort = try await picker.currentEffort(for: preset.model, excluding: before)
            guard effort == preset.effort else {
                throw SwitchError.message("Codex did not retain the requested reasoning effort.")
            }
            try picker.dismiss()
        } catch {
            throw SwitchError.message("\(preset.model) was selected, but the full preset could not be verified. Check the model menu before sending. \(error.localizedDescription)")
        }
    }
}

private enum SwitchError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

struct AccessibleControl {
    let element: AXUIElement
    let labels: [String]
    let inPicker: Bool
    let inWebContent: Bool

    func wasPresent(in controls: [AccessibleControl]) -> Bool {
        controls.contains { CFEqual(element, $0.element) }
    }
}

@MainActor
final class AccessiblePicker {
    let pid: pid_t
    let application: AXUIElement
    // Lock the operation to the same front window throughout asynchronous waits.
    private(set) var window: AXUIElement?
    let accessibility: any AccessibilityClient
    private var traversalSummary = ""

    init(pid: pid_t, accessibility: any AccessibilityClient = SystemAccessibilityClient(), application: AXUIElement? = nil) {
        self.pid = pid
        self.accessibility = accessibility
        self.application = application ?? AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(self.application, 0.25)
    }

    func prepare() async throws {
        try checkFocus()
        // This optional Electron extension is not implemented by every host.
        // An unsupported attribute does not mean that UI access was denied.
        let result = accessibility.set(application, "AXManualAccessibility", kCFBooleanTrue)
        guard [.success, .attributeUnsupported, .notImplemented].contains(result) else {
            throw SwitchError.message("Codex's accessibility request failed (\(result.rawValue)).")
        }
        for _ in 0..<20 {
            try checkFocus()
            if let focusedWindow = attribute(application, kAXFocusedWindowAttribute) {
                window = (focusedWindow as! AXUIElement)
                // Native title-bar buttons can appear before the web UI is ready.
                if try controls().contains(where: { $0.inWebContent || $0.inPicker || $0.labels.contains(where: PickerLabels.isPickerTrigger) }) { return }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SwitchError.message("Codex did not expose its chat window controls. Accessibility permission alone does not confirm model-picker access. Open a chat with its model picker visible, then retry.")
    }

    func checkFocus() throws {
        guard accessibility.foregroundPID == pid else {
            throw SwitchError.message("Codex lost focus; the switch stopped.")
        }
        if let window,
           let current = attribute(application, kAXFocusedWindowAttribute) {
            guard CFEqual(window, current) else {
                throw SwitchError.message("The active window changed; the switch stopped.")
            }
        }
    }

    func waitForShortcutRelease() async throws {
        // Carbon can report the number's release while Command/Control is held.
        // Keep the captured window and do not open or select anything until all
        // shortcut keys are up. A focus change cancels the pending selection.
        for _ in 0..<250 {
            try checkFocus()
            if !accessibility.shortcutKeysAreDown { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw SwitchError.message("Release the shortcut keys, then retry. No model selection was sent.")
    }

    func open(using controls: [AccessibleControl] = []) throws {
        let triggers = controls.filter { !$0.inPicker && $0.labels.contains(where: PickerLabels.isPickerTrigger) }
        if triggers.count == 1 {
            try press(triggers[0])
            return
        }
        try key(CGKeyCode(kVK_ANSI_M), flags: [.maskControl, .maskShift])
    }

    func dismiss() throws { try key(CGKeyCode(kVK_Escape), flags: []) }

    private func key(_ code: CGKeyCode, flags: CGEventFlags) throws {
        try checkFocus()
        try accessibility.postKey(code, flags: flags, pid: pid)
    }

    func press(_ control: AccessibleControl) throws {
        try checkFocus()
        let result = accessibility.press(control.element)
        guard result == .success else {
            throw SwitchError.message("The model menu did not accept the selection (\(result.rawValue)).")
        }
    }

    func activateMenuItem(_ control: AccessibleControl) async throws {
        guard control.inPicker else {
            throw SwitchError.message("The selected control is outside the model picker. No key was sent.")
        }
        // Codex's custom menu handles Space through its onSelect path. AXPress
        // may report success without invoking that handler in the native host.
        // Space is sent only after the exact, already matched item has focus.
        try await focus(control, description: "model menu item")
        try key(CGKeyCode(kVK_Space), flags: [])
    }

    private func focus(_ control: AccessibleControl, description: String) async throws {
        try checkFocus()
        let result = accessibility.set(control.element, kAXFocusedAttribute, kCFBooleanTrue)
        guard result == .success else {
            throw SwitchError.message("Could not focus Codex's \(description). No key was sent.")
        }
        // Accessibility focus changes can cross an asynchronous renderer boundary.
        for _ in 0..<10 {
            try checkFocus()
            if let focused = attribute(application, kAXFocusedUIElementAttribute), CFEqual(focused, control.element) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SwitchError.message("Codex did not focus its \(description). No key was sent.")
    }

    func waitForControl(excluding before: [AccessibleControl], stage: String, retryOpen: Bool = false, matching: ([String]) -> Bool) async throws -> AccessibleControl {
        for attempt in 0..<15 {
            try checkFocus()
            let matches = try controls().filter { $0.inPicker && !$0.wasPresent(in: before) && matching($0.labels) }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { throw SwitchError.message("Several matching menu items were found; choose the model manually.") }
            // AXPress can be accepted without opening a custom web trigger.
            // Codex's openModelPicker command is idempotent while already open.
            if retryOpen && attempt == 3 { try open() }
            try await Task.sleep(for: .milliseconds(100))
        }
        let exposed = try controls()
        let opening = retryOpen ? " The model-picker shortcut was also tried." : ""
        throw SwitchError.message("\(stage): the expected picker control was not exposed.\(opening) Diagnostics: \(exposed.count) controls, \(exposed.filter(\.inPicker).count) picker items; \(traversalSummary). Accessibility permission is granted.")
    }

    func isCombinedSelection(_ preset: ModelPreset, among before: [AccessibleControl]) throws -> Bool {
        try controls().contains { control in
            !control.inPicker && control.wasPresent(in: before)
                && control.labels.contains { PickerLabels.combined($0, matches: preset) }
        }
    }

    func currentEffort(for model: String, excluding before: [AccessibleControl], differentFrom previous: ReasoningEffort? = nil) async throws -> ReasoningEffort {
        for _ in 0..<15 {
            let labels = try controls().filter {
                $0.inPicker && !$0.wasPresent(in: before)
                    && $0.labels.contains { PickerLabels.isPowerControl($0) || PickerLabels.isModelListOpener($0) }
            }.flatMap(\.labels)
            if let effort = PickerLabels.selection(in: labels, model: model), effort != previous { return effort }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SwitchError.message("Could not read an updated Power value for \(model). The requested effort may be unavailable, or Codex may not expose its current selection.")
    }

    func adjustPower(to preset: ModelPreset, excluding before: [AccessibleControl]) async throws {
        var current = try await currentEffort(for: preset.model, excluding: before)
        let levels = ReasoningEffort.allCases
        let target = levels.firstIndex(of: preset.effort)!
        var visited: Set<ReasoningEffort> = []
        while current != preset.effort {
            guard visited.insert(current).inserted else {
                throw SwitchError.message("The Power control skipped the requested effort. Selection stopped.")
            }
            let power = try await waitForControl(excluding: before, stage: "Adjust Power") {
                $0.contains(where: PickerLabels.isPowerControl)
            }
            try await focus(power, description: "Power control")
            let code = levels.firstIndex(of: current)! < target ? kVK_RightArrow : kVK_LeftArrow
            try key(CGKeyCode(code), flags: [])
            current = try await currentEffort(for: preset.model, excluding: before, differentFrom: current)
        }
    }

    func controls() throws -> [AccessibleControl] {
        try checkFocus()
        var queue: [(element: AXUIElement, inPicker: Bool, webDepth: Int)] = [(window ?? application, false, 0)]
        if window != nil, let children = attribute(application, kAXChildrenAttribute) as? [AXUIElement] {
            queue += children.filter { attribute($0, kAXRoleAttribute) as? String == "AXMenu" }.map { ($0, true, 0) }
        }
        var result: [AccessibleControl] = []
        var visited = Set<AXUIElement>()
        var skippedWebAreas = 0
        var linkedPopups = 0
        var menuRoles = 0
        var expandedTriggers = 0
        var index = 0
        let deadline = Date().addingTimeInterval(1.5)
        while index < queue.count, index < 2500 {
            guard Date() < deadline else { throw SwitchError.message("Codex's accessibility tree took too long to respond.") }
            let entry = queue[index]
            let element = entry.element
            index += 1
            guard visited.insert(element).inserted else { continue }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            // Chromium demotes deeply wrapped web menus to AXGroup on macOS.
            // Their menu items retain AXMenuItem, including menuitemradio.
            // Recognize the item itself instead of requiring an AXMenu ancestor.
            let ariaRole = attribute(element, "AXARIARole") as? String ?? ""
            let isMenuRole = ["AXMenu", "AXMenuItem", "AXPopover", "AXDialog"].contains(role)
                || ["menu", "menuitem", "menuitemradio", "menuitemcheckbox"].contains(ariaRole)
            let inPicker = entry.inPicker || isMenuRole
            let webDepth = entry.webDepth + (role == "AXWebArea" ? 1 : 0)
            // Embedded browser pages are not the app's model picker.
            if webDepth > 1 { skippedWebAreas += 1; continue }
            if isMenuRole { menuRoles += 1 }
            // Do not read editable content, chat messages, or the transcript.
            if ["AXTextArea", "AXTextField", "AXStaticText"].contains(role) { continue }
            if (["AXButton", "AXMenuItem", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXComboBox"].contains(role)
                || ["menuitem", "menuitemradio", "menuitemcheckbox"].contains(ariaRole)),
               attribute(element, kAXEnabledAttribute) as? Bool != false {
                var labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
                    .compactMap { attribute(element, $0) as? String }.filter { !$0.isEmpty }
                // aria-label="Select model" hides the visible model/effort from
                // AXTitle. Read text descendants only inside picker controls.
                if inPicker { labels += controlText(element) }
                result.append(AccessibleControl(element: element, labels: labels, inPicker: inPicker, inWebContent: webDepth > 0))
                // aria-controls is exposed as AXLinkedUIElements by Chromium.
                // Follow the known model trigger's popup even when it is not
                // under the window's ordinary AXChildren hierarchy.
                if !inPicker, labels.contains(where: PickerLabels.isPickerTrigger),
                   attribute(element, kAXExpandedAttribute) as? Bool == true {
                    expandedTriggers += 1
                    let linked = attribute(element, kAXLinkedUIElementsAttribute) as? [AXUIElement] ?? []
                    linkedPopups += linked.count
                    queue.insert(contentsOf: linked.map { ($0, true, webDepth) }, at: index)
                }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, inPicker, webDepth) })
            }
        }
        traversalSummary = "\(expandedTriggers) expanded model buttons, \(menuRoles) menu roles, \(linkedPopups) popup links, \(skippedWebAreas) nested web areas skipped"
        if index < queue.count { throw SwitchError.message("The accessibility tree is too large to select safely.") }
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        accessibility.attribute(element, name)
    }

    private func controlText(_ element: AXUIElement) -> [String] {
        var queue = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        var text: [String] = []
        var index = 0
        while index < queue.count, index < 64 {
            let child = queue[index]
            index += 1
            let role = attribute(child, kAXRoleAttribute) as? String ?? ""
            if role == "AXStaticText" {
                if let value = attribute(child, kAXValueAttribute) as? String, !value.isEmpty, value.count <= 160 {
                    text.append(value)
                }
            } else if ["AXGroup", "AXUnknown"].contains(role),
                      let children = attribute(child, kAXChildrenAttribute) as? [AXUIElement] {
                queue.insert(contentsOf: children, at: index)
            }
        }
        return text.isEmpty ? [] : text + [text.joined(separator: " ")]
    }
}
