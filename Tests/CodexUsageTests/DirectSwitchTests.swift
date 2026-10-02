import Foundation
import Testing
@testable import CodexUsageAutomation
import CodexUsageCore

@Test func directTargetRejectsAuxiliaryOrAmbiguousWindows() throws {
    let target = DebugTarget(type: "page", url: "app://-/index.html", webSocketDebuggerUrl: "ws://127.0.0.1:12345/test")
    let auxiliary = DebugTarget(type: "page", url: "app://-/index.html?initialRoute=overlay", webSocketDebuggerUrl: "ws://127.0.0.1:12345/other")
    #expect(try DebugTarget.mainWindow(in: [target, auxiliary]).url == target.url)
    #expect(throws: DirectSwitchError.self) { try DebugTarget.mainWindow(in: [target, target]) }
    #expect(throws: DirectSwitchError.self) { try DebugTarget.mainWindow(in: [auxiliary]) }
}

private func withFixture(_ mode: String, operation: (Int) async throws -> Void) async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DirectSwitching/cdp-fixture.mjs")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", fixture.path, mode]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    try process.run()
    defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
    var data = Data()
    while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
        if byte[0] == 10 { break }
        data.append(byte)
        guard data.count < 10 else { throw DirectSwitchError.message("Invalid fixture port.") }
    }
    let port = try #require(Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    try await operation(port)
}

@Test func directWebSocketAppliesAndChecksAllPresets() async throws {
    try await withFixture("success") { port in
        let switcher = DirectModelSwitcher(port: port)
        for preset in PresetConfiguration.defaults.presets {
            let result = try await switcher.apply(preset)
            #expect(PickerLabels.model(result.model, matches: preset.model))
            #expect(result.effort == preset.effort.rawValue)
        }
    }
}

@Test func directWebSocketAcceptsCatalogDisplayNameWithUnrelatedSlug() async throws {
    let preset = try JSONDecoder().decode(ModelPreset.self, from: Data(#"{"slot":1,"model":"My Custom Model","effort":"xhigh"}"#.utf8))
    try await withFixture("alias") { port in
        let result = try await DirectModelSwitcher(port: port).apply(preset)
        #expect(result.model == "provider:special-v2")
        #expect(result.displayName == "My Custom Model")
        #expect(result.effort == "xhigh")
    }
}

@Test(arguments: ["exception", "exception-stack", "mismatch", "effort-mismatch", "remote", "stall"])
func directWebSocketRejectsFailureInsteadOfReportingApplied(_ mode: String) async throws {
    try await withFixture(mode) { port in
        let expected = ["exception": "Server rejected", "exception-stack": "Open one active Codex chat.", "mismatch": "different model", "effort-mismatch": "different model", "remote": "local address", "stall": "timed out"][mode]!
        do {
            _ = try await DirectModelSwitcher(port: port).apply(PresetConfiguration.defaults.presets[1])
            Issue.record("An unconfirmed update was accepted.")
        } catch {
            #expect(error.localizedDescription.contains(expected))
            if mode == "exception-stack" {
                #expect(error.localizedDescription == expected)
            }
        }
    }
}

@Test func deckWebSocketReadsTypedStateAndAppliesExactTarget() async throws {
    try await withFixture("deck") { port in
        let switcher = DirectModelSwitcher(port: port)
        let state = try await switcher.deckState()
        #expect(state.targetID == "chat-1")
        #expect(state.title == "Fixture chat")
        #expect(state.model == "gpt-6-astra")
        #expect(state.effort == "high")
        let result = try await switcher.applyRemote(PresetConfiguration.defaults.presets[0], targetID: state.targetID)
        #expect(result.model == "gpt-6-astra")
        #expect(result.effort == "ultra")
        for target in ["previous-chat", "quoted-\"-target\nwith-newline"] {
            do {
                _ = try await switcher.applyRemote(PresetConfiguration.defaults.presets[0], targetID: target)
                Issue.record("A stale Web Deck target was accepted.")
            } catch {
                #expect(error.localizedDescription.contains("no longer active"))
            }
        }
    }
}

@Test func deckWebSocketRejectsMissingIdentityAndInvalidTarget() async throws {
    try await withFixture("deck-invalid") { port in
        let switcher = DirectModelSwitcher(port: port)
        await #expect(throws: DirectSwitchError.self) { try await switcher.deckState() }
        await #expect(throws: DirectSwitchError.self) {
            try await switcher.applyRemote(PresetConfiguration.defaults.presets[0], targetID: "")
        }
    }
}
