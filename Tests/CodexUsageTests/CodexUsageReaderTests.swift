import Foundation
import Testing
@testable import CodexUsageCore

@Test
func readerFindsLatestRateLimitSnapshot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageTests-\(UUID().uuidString)", isDirectory: true)
    let sessions = root.appendingPathComponent("sessions/2026/06/11", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let log = sessions.appendingPathComponent("session.jsonl")
    let first = #"""
{"timestamp":"2026-06-11T07:10:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1781172012},"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1781742997},"credits":null,"plan_type":"pro"}}}
"""#
    let second = #"""
{"timestamp":"2026-06-11T07:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":18.0,"window_minutes":300,"resets_at":1781172012},"secondary":{"used_percent":4.0,"window_minutes":10080,"resets_at":1781742997},"credits":null,"plan_type":"pro"}}}
"""#
    try "\(first)\n\(second)\n".write(to: log, atomically: true, encoding: .utf8)

    let snapshot = try CodexUsageReader().latestSnapshot(
        codexDirectory: root
    )

    #expect(snapshot.primary?.usedPercent == 18.0)
    #expect(snapshot.secondary?.usedPercent == 4.0)
    #expect(snapshot.primary?.windowMinutes == 300)
    #expect(snapshot.secondary?.windowMinutes == 10080)
    #expect(snapshot.planType == "pro")

    try? FileManager.default.removeItem(at: root)
}

@Test
func readerPreservesExpiredUsageUntilNewCodexEvents() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageTests-\(UUID().uuidString)", isDirectory: true)
    let sessions = root.appendingPathComponent("sessions/2026/06/11", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let log = sessions.appendingPathComponent("session.jsonl")
    let event = #"""
{"timestamp":"2026-06-11T07:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1781172012},"secondary":{"used_percent":4.0,"window_minutes":10080,"resets_at":1781742997},"credits":null,"plan_type":"pro"}}}
"""#
    try "\(event)\n".write(to: log, atomically: true, encoding: .utf8)

    let snapshot = try CodexUsageReader().latestSnapshot(
        codexDirectory: root
    )

    #expect(snapshot.primary?.usedPercent == 82)
    #expect(snapshot.primary?.remainingPercent == 18)
    #expect(snapshot.primary?.isExpired(at: Date(timeIntervalSince1970: 1_781_172_100)) == true)
    #expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_781_172_012))
    #expect(snapshot.secondary?.usedPercent == 4.0)

    try? FileManager.default.removeItem(at: root)
}
