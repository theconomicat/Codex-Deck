import ApplicationServices
import Carbon
import Testing
@testable import CodexUsageAutomation
@testable import CodexUsageCore

// Historical Accessibility scenarios retain their original three-preset sequence.
// The active direct backend tests the current five-slot defaults separately.
private let legacyAccessibilityPresets = [
    ModelPreset(slot: 1, model: "GPT-6 Astra", effort: .xhigh),
    ModelPreset(slot: 2, model: "GPT-6.1 Sol", effort: .xhigh),
    ModelPreset(slot: 3, model: "GPT-6.1 Sol", effort: .high)
]

@Test @MainActor
func menuPressAcceptedWithoutSelectionStillAppliesAllPresetsThroughKeyboard() async throws {
    let fixture = PickerFixture()
    fixture.menuPressIgnored = true
    fixture.model = "6 Astra"
    fixture.effort = .xhigh
    for slot in [2, 3, 1] {
        let preset = legacyAccessibilityPresets[slot - 1]
        try await fixture.picker().apply(preset)
        #expect(PickerLabels.model(fixture.model, matches: preset.model))
        #expect(fixture.effort == preset.effort)
        #expect(!fixture.open)
    }
    #expect(fixture.keyboardSelections == [.opener, .sol, .opener, .sol, .opener, .astra])
}

@Test @MainActor
func unconfirmedMenuFocusNeverSendsSpaceOrChangesModel() async {
    let fixture = PickerFixture()
    fixture.menuPressIgnored = true
    fixture.ignoreFocusRequest = true
    do {
        try await fixture.picker().apply(legacyAccessibilityPresets[1])
        Issue.record("An unfocused menu control was activated")
    } catch {
        #expect(error.localizedDescription.contains("focus"))
        #expect(fixture.keyboardSelections.isEmpty)
        #expect(fixture.model == "6 Sol")
        #expect(fixture.effort == .medium)
    }
}

@Test @MainActor
func completePickerFlowEnablesElectronBeforeReadingAndAppliesAllThreePresets() async throws {
    let fixture = PickerFixture()
    let picker = fixture.picker()
    for preset in legacyAccessibilityPresets {
        try await picker.apply(preset)
        #expect(PickerLabels.model(fixture.model, matches: preset.model))
        #expect(fixture.effort == preset.effort)
        #expect(!fixture.open)
    }
    #expect(fixture.operations.first == "enable")
    #expect(fixture.operations.contains("model-list"))
    #expect(fixture.keys == [CGKeyCode(kVK_RightArrow), CGKeyCode(kVK_RightArrow), CGKeyCode(kVK_LeftArrow)])
    #expect(!fixture.keys.contains(CGKeyCode(kVK_Return)))
    #expect(!fixture.operations.contains("embedded-content"))
}

@Test @MainActor
func heldShortcutModifiersDelayEveryPickerActionUntilRelease() async throws {
    let fixture = PickerFixture()
    fixture.shortcutKeysAreDown = true
    let task = Task { try await fixture.picker().apply(legacyAccessibilityPresets[0]) }
    try await Task.sleep(for: .milliseconds(120))
    #expect(fixture.operations == ["enable"])
    #expect(!fixture.open)
    #expect(fixture.keys.isEmpty)
    fixture.shortcutKeysAreDown = false
    try await task.value
    #expect(fixture.model == "6 Astra")
    #expect(fixture.effort == .xhigh)
    #expect(!fixture.open)
}

@Test @MainActor
func focusLossWhileShortcutIsHeldCancelsBeforeOpeningAnything() async throws {
    let fixture = PickerFixture()
    fixture.shortcutKeysAreDown = true
    let task = Task { try await fixture.picker().apply(legacyAccessibilityPresets[0]) }
    try await Task.sleep(for: .milliseconds(120))
    fixture.foregroundPID = 42
    fixture.shortcutKeysAreDown = false
    do {
        try await task.value
        Issue.record("A pending shortcut followed focus to another app")
    } catch {
        #expect(error.localizedDescription.contains("lost focus"))
        #expect(fixture.operations == ["enable"])
        #expect(fixture.keys.isEmpty)
        #expect(fixture.model == "6 Sol")
    }
}

@Test @MainActor
func pickerRetriesAnAlreadyOpenMenuAndUnderstandsKoreanControls() async throws {
    let fixture = PickerFixture()
    fixture.korean = true
    fixture.open = true
    try await fixture.picker().apply(legacyAccessibilityPresets[0])
    #expect(fixture.effort == .xhigh)
    #expect(!fixture.open)
}

@Test(arguments: [false, true]) @MainActor
func deeplyNestedWebMenuItemsWorkWithoutAnAXMenuAncestor(alreadyOpen: Bool) async throws {
    let fixture = PickerFixture()
    // Chromium exposes role=menu as AXGroup when menu items are more than
    // two levels deep. Codex's animated picker has these wrapper groups.
    fixture.groupedMenu = true
    fixture.open = alreadyOpen
    fixture.korean = alreadyOpen
    for preset in legacyAccessibilityPresets {
        try await fixture.picker().apply(preset)
        #expect(PickerLabels.model(fixture.model, matches: preset.model))
        #expect(fixture.effort == preset.effort)
        #expect(!fixture.open)
    }
    #expect(!fixture.operations.contains("embedded-content"))
    #expect(!fixture.keys.contains(CGKeyCode(kVK_Return)))
}

@Test @MainActor
func acceptedPressThatDoesNotOpenPopupFallsBackToCodexCommand() async throws {
    let fixture = PickerFixture()
    fixture.triggerIgnoresPress = true
    try await fixture.picker().apply(legacyAccessibilityPresets[0])
    #expect(fixture.operations.prefix(4) == ["enable", "open", "shortcut", "model-list"])
    #expect(fixture.effort == .xhigh)
    #expect(!fixture.open)
}

@Test @MainActor
func modelTriggerLinkedPopupCanLiveOutsideWindowChildren() async throws {
    let fixture = PickerFixture()
    fixture.groupedMenu = true
    fixture.linkedMenuOnly = true
    for preset in legacyAccessibilityPresets {
        try await fixture.picker().apply(preset)
        #expect(PickerLabels.model(fixture.model, matches: preset.model))
        #expect(fixture.effort == preset.effort)
        #expect(!fixture.open)
    }
    #expect(!fixture.operations.contains("embedded-content"))
}

@Test @MainActor
func ariaMenuItemsAreRecognizedWhenNativeRoleIsGroup() async throws {
    let fixture = PickerFixture()
    fixture.groupedMenu = true
    fixture.ariaMenuItems = true
    try await fixture.picker().apply(legacyAccessibilityPresets[1])
    #expect(fixture.model == "6.1 Sol")
    #expect(fixture.effort == .xhigh)
    #expect(!fixture.open)
}

@Test @MainActor
func absentPopupStopsWithTraversalDiagnosticsAndNoSelection() async {
    let fixture = PickerFixture()
    fixture.triggerIgnoresPress = true
    fixture.shortcutIgnoresOpen = true
    do {
        try await fixture.picker().apply(legacyAccessibilityPresets[0])
        Issue.record("An absent popup was treated as selected")
    } catch {
        #expect(error.localizedDescription.contains("popup links"))
        #expect(error.localizedDescription.contains("nested web areas skipped"))
        #expect(fixture.operations == ["enable", "open", "shortcut"])
        #expect(fixture.keys.isEmpty)
        #expect(fixture.model == "6 Sol")
    }
}

@Test @MainActor
func unavailableEffortStopsInsteadOfOscillatingOrClaimingSuccess() async {
    let fixture = PickerFixture()
    fixture.supported.removeAll { $0 == .xhigh }
    do {
        try await fixture.picker().apply(legacyAccessibilityPresets[1])
        Issue.record("Unsupported effort was incorrectly reported as applied")
    } catch {
        #expect(fixture.effort != .xhigh)
        #expect(fixture.keys.count <= 3)
    }
}

@Test @MainActor
func focusLossStopsBeforePostingAnyArrowKeys() async {
    let fixture = PickerFixture()
    fixture.loseFocusAfterModelSelection = true
    do {
        try await fixture.picker().apply(legacyAccessibilityPresets[0])
        Issue.record("Focus loss was not detected")
    } catch {
        #expect(fixture.keys.isEmpty)
    }
}

@Test @MainActor
func electronAccessibilityFailureStopsBeforeOpeningThePicker() async {
    let fixture = PickerFixture()
    fixture.enableResult = .apiDisabled
    do {
        try await fixture.picker().apply(legacyAccessibilityPresets[0])
        Issue.record("Accessibility initialization failure was not detected")
    } catch {
        #expect(fixture.operations == ["enable"])
    }
}

@Test(arguments: [AXError.attributeUnsupported, .notImplemented]) @MainActor
func optionalAccessibilityAttributeDoesNotBlockAnExposedPicker(_ result: AXError) async throws {
    let fixture = PickerFixture()
    fixture.enabled = true // The UI can already be read without Electron's opt-in.
    fixture.enableResult = result
    try await fixture.picker().apply(legacyAccessibilityPresets[0])
    #expect(fixture.model == "6 Astra")
    #expect(fixture.effort == .xhigh)
    #expect(!fixture.open)
}

@Test @MainActor
func unsupportedAttributeWithoutAnExposedUIStopsBeforeInput() async {
    let fixture = PickerFixture()
    fixture.enableResult = .attributeUnsupported
    do {
        try await fixture.picker().apply(legacyAccessibilityPresets[0])
        Issue.record("An absent UI was incorrectly treated as ready")
    } catch {
        #expect(error.localizedDescription.contains("window controls"))
        #expect(fixture.operations == ["enable"])
        #expect(fixture.keys.isEmpty)
    }
}

@Test @MainActor
func nativeWindowButtonsDoNotCountAsAReadyModelPicker() async throws {
    let fixture = PickerFixture()
    fixture.webExposureDelay = 3
    try await fixture.picker().apply(legacyAccessibilityPresets[0])
    #expect(fixture.windowReads > 3)
    #expect(fixture.effort == .xhigh)
}

/// A controlled accessibility boundary, not a claim of live Codex verification.
/// The hierarchy and compact/list/Power transitions follow Codex 26.928's UI.
@MainActor
private final class PickerFixture: AccessibilityClient {
    var shortcutKeysAreDown = false
    var menuPressIgnored = false
    var ignoreFocusRequest = false
    var keyboardSelections: [Node] = []
    enum Node: Int, CaseIterable { case app, window, web, composer, menu, opener, power, astra, sol, embeddedWeb, spoof, input, close, track, panel, content }
    let elements = Node.allCases.map { AXUIElementCreateApplication(pid_t(800_000 + $0.rawValue)) }
    var foregroundPID: pid_t? = 800_000
    var enabled = false
    var webExposureDelay = 0
    var windowReads = 0
    var enableResult = AXError.success
    var korean = false
    var groupedMenu = false
    var linkedMenuOnly = false
    var ariaMenuItems = false
    var triggerIgnoresPress = false
    var shortcutIgnoresOpen = false
    var open = false
    var advanced = false
    var focused: Node = .composer
    var model = "6 Sol"
    var effort = ReasoningEffort.medium
    var supported: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max, .ultra]
    var loseFocusAfterModelSelection = false
    var operations: [String] = []
    var keys: [CGKeyCode] = []

    func picker() -> AccessiblePicker {
        AccessiblePicker(pid: 800_000, accessibility: self, application: element(.app))
    }
    func element(_ node: Node) -> AXUIElement { elements[node.rawValue] }
    func node(_ element: AXUIElement) -> Node { Node.allCases.first { CFEqual(self.element($0), element) }! }

    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        let node = node(element)
        if name == kAXFocusedWindowAttribute { return self.element(.window) }
        if name == kAXFocusedUIElementAttribute { return self.element(focused) }
        if name == kAXEnabledAttribute { return kCFBooleanTrue }
        if name == kAXExpandedAttribute, node == .composer { return open ? kCFBooleanTrue : kCFBooleanFalse }
        if name == kAXLinkedUIElementsAttribute, node == .composer, open, linkedMenuOnly {
            // Duplicate references must not create ambiguous matching items.
            return [self.element(.menu), self.element(.menu)] as CFArray
        }
        if name == "AXARIARole", ariaMenuItems, [.opener, .power, .astra, .sol].contains(node) {
            return "menuitem" as CFString
        }
        if name == kAXRoleAttribute {
            if [.opener, .power, .astra, .sol].contains(node) {
                if ariaMenuItems { return "AXGroup" as CFString }
                if linkedMenuOnly { return "AXButton" as CFString }
            }
            let roles: [Node: String] = [.app: "AXApplication", .window: "AXWindow", .web: "AXWebArea", .composer: "AXPopUpButton", .menu: groupedMenu ? "AXGroup" : "AXMenu", .embeddedWeb: "AXWebArea", .input: "AXTextArea", .close: "AXButton", .track: "AXGroup", .panel: "AXGroup", .content: "AXGroup"]
            return (roles[node] ?? "AXMenuItem") as CFString
        }
        if name == kAXChildrenAttribute {
            let children: [Node]
            switch node {
            case .app: children = [.window]
            case .window:
                windowReads += 1
                children = [.close] + (enabled && windowReads > webExposureDelay ? [.web] : [])
            case .web: children = [.composer, .input, .embeddedWeb] + (open && !linkedMenuOnly ? [.menu] : [])
            case .menu: children = groupedMenu ? [.track] : advanced ? [.astra, .sol] : [.opener, .power]
            case .track: children = [.panel]
            case .panel: children = [.content]
            case .content: children = advanced ? [.astra, .sol] : [.opener, .power]
            case .embeddedWeb: children = [.spoof]
            default: children = []
            }
            return children.map { self.element($0) } as CFArray
        }
        if name == kAXTitleAttribute {
            let labels: [Node: String] = [.composer: "\(model) \(effort.title)", .opener: korean ? "모델 선택" : "Select model", .power: korean ? "파워" : "Power", .astra: "6 Astra", .sol: "6.1 Sol", .spoof: "6.1 Sol", .close: "Close"]
            return labels[node].map { $0 as CFString }
        }
        if name == kAXHelpAttribute {
            if node == .composer { return "Select model" as CFString }
            if node == .power {
                let label = effort == .medium ? "Standard" : effort == .high ? "Extended" : effort.title
                return "\(model) \(label), 3 of 6. Use Left and Right arrow keys to adjust power" as CFString
            }
        }
        return nil
    }

    func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
        if name == "AXManualAccessibility" {
            operations.append("enable")
            if enableResult == .success { enabled = true }
            return enableResult
        }
        if name == kAXFocusedAttribute {
            if !ignoreFocusRequest { focused = node(element) }
            return .success
        }
        return .attributeUnsupported
    }

    func press(_ element: AXUIElement) -> AXError {
        if menuPressIgnored, [.opener, .astra, .sol].contains(node(element)) { return .success }
        return select(element)
    }

    private func select(_ element: AXUIElement) -> AXError {
        switch node(element) {
        case .composer:
            operations.append("open")
            if !triggerIgnoresPress { open = true; advanced = false }
        case .opener: operations.append("model-list"); advanced = true
        case .astra, .sol:
            model = node(element) == .astra ? "6 Astra" : "6.1 Sol"
            advanced = false
            if loseFocusAfterModelSelection { foregroundPID = 42 }
        case .spoof: operations.append("embedded-content")
        default: return .actionUnsupported
        }
        return .success
    }

    func postKey(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t) throws {
        if code == kVK_Space {
            #expect(open)
            #expect(flags.isEmpty)
            #expect([Node.opener, .astra, .sol].contains(focused))
            keyboardSelections.append(focused)
            _ = select(element(focused))
            return
        }
        if code == kVK_Escape { open = false; return }
        if code == kVK_ANSI_M {
            #expect(flags == [.maskControl, .maskShift])
            operations.append("shortcut")
            if !shortcutIgnoresOpen { open = true }
            return
        }
        #expect(code == kVK_RightArrow || code == kVK_LeftArrow)
        #expect(focused == .power)
        #expect(flags.isEmpty)
        keys.append(code)
        let direction = code == kVK_RightArrow ? 1 : -1
        let index = supported.firstIndex(of: effort)!
        effort = supported[max(0, min(supported.count - 1, index + direction))]
    }
}
