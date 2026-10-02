import Foundation
import Testing
@testable import CodexUsageCore

@Test
func readerAcceptsWeeklyOnlyLimits() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let sessions = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let event = #"""
    {"timestamp":"2026-10-02T04:38:04.187Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":79,"window_minutes":10080,"resets_at":1791163010},"secondary":null,"plan_type":"pro"}}}
    """#
    try event.write(to: sessions.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    let snapshot = try CodexUsageReader().latestSnapshot(codexDirectory: root)
    #expect(snapshot.primary?.windowMinutes == 10080)
    #expect(snapshot.primary?.remainingPercent == 21)
    #expect(snapshot.secondary == nil)
    #expect(snapshot.windows.map(\.label) == ["1w"])
}

@Test(arguments: ["null", "missing"])
func readerAcceptsAbsentPrimary(_ mode: String) throws {
    let primary = mode == "null" ? #""primary":null,"# : ""
    let snapshot = try readLimits(["{\(primary)\"secondary\":{\"used_percent\":20,\"window_minutes\":10080}}"])
    #expect(snapshot.primary == nil)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.secondary?.remainingPercent == 80)
}

@Test
func latestEmptyWindowsDoNotReuseOldQuota() throws {
    let snapshot = try readLimits([
        #"{"primary":{"used_percent":10,"window_minutes":300},"secondary":{"used_percent":20,"window_minutes":10080}}"#,
        #"{"primary":null,"secondary":null}"#
    ])
    #expect(snapshot.windows.isEmpty)
}

@Test
func weeklyOnlyReplacesLegacyWindowsAndIgnoresOtherBuckets() throws {
    let snapshot = try readLimits([
        #"{"primary":{"used_percent":10,"window_minutes":300},"secondary":{"used_percent":20,"window_minutes":10080}}"#,
        #"{"limit_id":"codex","primary":{"used_percent":79,"window_minutes":10080},"secondary":null}"#,
        #"{"limit_id":"codex_other","primary":{"used_percent":99,"window_minutes":60}}"#
    ])
    #expect(snapshot.windows.map(\.label) == ["1w"])
    #expect(snapshot.primary?.remainingPercent == 21)
}

@Test
func invalidWindowsAreNotPresentedAsQuota() throws {
    let snapshot = try readLimits([#"{"primary":{"used_percent":20,"window_minutes":0}}"#])
    #expect(snapshot.windows.isEmpty)
}

private func readLimits(_ limits: [String]) throws -> CodexUsageSnapshot {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let sessions = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let lines = limits.enumerated().map { index, value in
        "{\"timestamp\":\"2026-10-02T04:38:0\(index)Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":\(value)}}"
    }
    try (lines.joined(separator: "\n") + "\n{partial").write(to: sessions.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    return try CodexUsageReader().latestSnapshot(codexDirectory: root)
}
