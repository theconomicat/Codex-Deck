import Foundation

/// Session logs are append-only. Cache file cursors so refreshes read new bytes,
/// while still discovering new/archived logs and detecting replacement/truncation.
public final class CodexUsageReader: @unchecked Sendable {
    private struct FileState {
        var inode: UInt64
        var size: UInt64
        var modified: Date
        var offset: UInt64 = 0
        var snapshot: CodexUsageSnapshot?
    }

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private var files: [URL: FileState] = [:]
    private static let eventMarker = Data(#""token_count""#.utf8)
    private static let limitsMarker = Data(#""rate_limits""#.utf8)
    // Internal diagnostics let regression tests verify that unchanged logs are not reread.
    private var scanBytesRead: UInt64 = 0
    var lastScanBytesRead: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return scanBytesRead
    }

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom(Self.decodeISO8601Date)
    }

    public func latestSnapshot(codexDirectory: URL = defaultCodexDirectory()) throws -> CodexUsageSnapshot {
        lock.lock()
        defer { lock.unlock() }
        scanBytesRead = 0
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: codexDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            files.removeAll()
            throw CodexUsageError.codexDirectoryMissing(codexDirectory)
        }

        let logs = sessionLogFiles(in: codexDirectory)
        let paths = Set(logs)
        files = files.filter { paths.contains($0.key) }
        for url in logs {
            autoreleasepool { update(url) }
        }
        guard let latest = files.values.compactMap(\.snapshot).max(by: { $0.timestamp < $1.timestamp }) else {
            throw CodexUsageError.noUsageEventsFound(codexDirectory)
        }
        return latest
    }

    public static func defaultCodexDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private static func decodeISO8601Date(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
        if let date = try? Date.ISO8601FormatStyle().parse(value) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
    }

    private func sessionLogFiles(in codexDirectory: URL) -> [URL] {
        ["sessions", "archived_sessions"].flatMap { directory -> [URL] in
            guard let enumerator = fileManager.enumerator(
                at: codexDirectory.appendingPathComponent(directory, isDirectory: true),
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ) else { return [] }
            return enumerator.compactMap { item -> URL? in
                guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
                return url
            }
        }
    }

    private func update(_ url: URL) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return }
        if let old = files[url], old.inode == inode, old.size == size, old.modified == modified { return }
        var state = files[url] ?? FileState(inode: inode, size: size, modified: modified)
        if state.inode != inode || size < state.size || (size == state.size && modified != state.modified) {
            state = FileState(inode: inode, size: size, modified: modified)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: state.offset)
            var remaining = size - state.offset
            var buffer = Data()
            while remaining > 0 {
                // Release transient Foundation/decoder objects throughout the
                // initial scan; a single session log can be hundreds of MiB.
                let readChunk = try autoreleasepool { () throws -> Bool in
                    guard let chunk = try handle.read(upToCount: Int(min(remaining, 262_144))), !chunk.isEmpty else { return false }
                    scanBytesRead += UInt64(chunk.count)
                    remaining -= UInt64(chunk.count)
                    buffer.append(chunk)
                    var start = buffer.startIndex
                    while let newline = buffer[start...].firstIndex(of: 10) {
                        consider(buffer[start..<newline], in: &state)
                        start = newline + 1
                    }
                    state.offset += UInt64(start - buffer.startIndex)
                    buffer = Data(buffer[start...])
                    return true
                }
                if !readChunk { break }
            }
            // A complete JSON event may lack its final newline. Keep its cursor
            // at the line start so a partial write is retried on the next append.
            if !buffer.isEmpty { consider(buffer, in: &state) }
            state.inode = inode
            state.size = size
            state.modified = modified
            files[url] = state
        } catch {
            // Do not advance the saved cursor on a failed read.
        }
    }

    private func consider(_ line: Data, in state: inout FileState) {
        guard line.range(of: Self.eventMarker) != nil, line.range(of: Self.limitsMarker) != nil,
              let event = try? decoder.decode(CodexEvent.self, from: line), let snapshot = event.snapshot else { return }
        if state.snapshot == nil || snapshot.timestamp > state.snapshot!.timestamp { state.snapshot = snapshot }
    }
}

private struct CodexEvent: Decodable {
    let timestamp: Date
    let type: String
    let payload: Payload

    var snapshot: CodexUsageSnapshot? {
        guard type == "event_msg", payload.type == "token_count", let rateLimits = payload.rateLimits else {
            return nil
        }
        // Model-specific buckets must not overwrite the account-wide Codex quota.
        guard rateLimits.limitID == nil || rateLimits.limitID == "codex" else { return nil }

        return CodexUsageSnapshot(
            timestamp: timestamp,
            primary: rateLimits.primary?.asUsageWindow,
            secondary: rateLimits.secondary?.asUsageWindow,
            planType: rateLimits.planType,
            limitID: rateLimits.limitID
        )
    }

    struct Payload: Decodable {
        let type: String
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }
}

private struct RateLimits: Decodable {
    let limitID: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    var asUsageWindow: UsageWindow? {
        guard windowMinutes > 0, usedPercent.isFinite else { return nil }
        return UsageWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
