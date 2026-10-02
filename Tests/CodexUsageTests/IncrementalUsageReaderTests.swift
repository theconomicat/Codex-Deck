import Foundation
import Testing
@testable import CodexUsageCore

private func event(_ second: Int, used: Int) -> String {
    #"{"timestamp":"2026-10-03T00:00:"# + String(format: "%02d", second) + #"Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","secondary":{"used_percent":\#(used),"window_minutes":10080}}}}"#
}

private func logs() throws -> (URL, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return (root, folder.appendingPathComponent("session.jsonl"))
}

private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}

@Test func usageReaderSkipsUnchangedLogsAndReadsOnlyAppendedBytes() throws {
    let (root, log) = try logs()
    defer { try? FileManager.default.removeItem(at: root) }
    try (event(1, used: 10) + "\n").write(to: log, atomically: true, encoding: .utf8)
    let reader = CodexUsageReader()
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 10)
    #expect(reader.lastScanBytesRead > 0)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 10)
    #expect(reader.lastScanBytesRead == 0)
    let addition = event(2, used: 20) + "\n"
    try append(addition, to: log)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 20)
    #expect(reader.lastScanBytesRead == UInt64(addition.utf8.count))
}

@Test func usageReaderRetriesPartialLastLineAndAcceptsNoFinalNewline() throws {
    let (root, log) = try logs()
    defer { try? FileManager.default.removeItem(at: root) }
    let next = event(2, used: 20)
    try (event(1, used: 10) + "\n" + next.prefix(45)).write(to: log, atomically: true, encoding: .utf8)
    let reader = CodexUsageReader()
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 10)
    try append(String(next.dropFirst(45)), to: log)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 20)
    try append("\n" + event(3, used: 30) + "\n", to: log)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 30)
}

@Test func usageReaderHandlesReplacementTruncationDeletionAndNewArchive() throws {
    let (root, log) = try logs()
    defer { try? FileManager.default.removeItem(at: root) }
    try (event(8, used: 80) + "\n" + String(repeating: "x", count: 1024) + "\n").write(to: log, atomically: true, encoding: .utf8)
    let reader = CodexUsageReader()
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 80)
    // Truncation must invalidate the previous latest event, even when its date was newer.
    try (event(2, used: 20) + "\n").write(to: log, atomically: false, encoding: .utf8)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 20)
    try (event(3, used: 30) + "\n").write(to: log, atomically: true, encoding: .utf8)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 30)
    let archive = root.appendingPathComponent("archived_sessions")
    try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    try (event(1, used: 10) + "\n").write(to: archive.appendingPathComponent("old.jsonl"), atomically: true, encoding: .utf8)
    try FileManager.default.removeItem(at: log)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 10)
}

@Test func usageReaderPreservesLatestTimestampAcrossChunkBoundaries() throws {
    let (root, log) = try logs()
    defer { try? FileManager.default.removeItem(at: root) }
    // Put a usage record across the 256 KiB read boundary; later lines may be older.
    let content = String(repeating: "x", count: 262_100) + "\n" + event(8, used: 80) + "\n" + event(2, used: 20) + "\n"
    try content.write(to: log, atomically: true, encoding: .utf8)
    let reader = CodexUsageReader()
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 80)
    #expect(reader.lastScanBytesRead == UInt64(content.utf8.count))
}


@Test func usageReaderInvalidatesSameSizeRewrite() throws {
    let (root, log) = try logs()
    defer { try? FileManager.default.removeItem(at: root) }
    try (event(8, used: 80) + "\n").write(to: log, atomically: false, encoding: .utf8)
    let reader = CodexUsageReader()
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 80)
    let rewritten = event(2, used: 20) + "\n"
    try rewritten.write(to: log, atomically: false, encoding: .utf8)
    // Explicitly move mtime so this test does not depend on filesystem clock resolution.
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 2)], ofItemAtPath: log.path)
    #expect(try reader.latestSnapshot(codexDirectory: root).secondary?.usedPercent == 20)
    #expect(reader.lastScanBytesRead == UInt64(rewritten.utf8.count))
}

@Test func usageReaderAcceptsFractionalAndOffsetISODatesAcrossAppends() throws {
    let (root, log) = try logs()
    defer { try? FileManager.default.removeItem(at: root) }
    let initial = event(1, used: 10).replacingOccurrences(of: "00:00:01Z", with: "09:00:01.123456+09:00")
    try (initial + "\n").write(to: log, atomically: true, encoding: .utf8)
    let reader = CodexUsageReader()
    let first = try reader.latestSnapshot(codexDirectory: root)
    #expect(first.secondary?.usedPercent == 10)
    try append(event(2, used: 20) + "\n", to: log)
    let second = try reader.latestSnapshot(codexDirectory: root)
    #expect(second.secondary?.usedPercent == 20)
    #expect(abs(second.timestamp.timeIntervalSince(first.timestamp) - 0.876544) < 0.00001)
}

@Test func usageReaderSerializesConcurrentRefreshes() async throws {
    let (root, log) = try logs()
    defer { try? FileManager.default.removeItem(at: root) }
    try (event(1, used: 10) + "\n").write(to: log, atomically: true, encoding: .utf8)
    let reader = CodexUsageReader()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<12 {
            group.addTask {
                let snapshot = try reader.latestSnapshot(codexDirectory: root)
                #expect(snapshot.secondary?.usedPercent == 10)
                _ = reader.lastScanBytesRead
            }
        }
        try await group.waitForAll()
    }
    #expect(reader.lastScanBytesRead == 0)
}
