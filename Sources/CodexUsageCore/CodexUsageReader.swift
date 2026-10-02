import Foundation

public final class CodexUsageReader: @unchecked Sendable {
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom(Self.decodeISO8601Date)
    }

    public func latestSnapshot(codexDirectory: URL = defaultCodexDirectory()) throws -> CodexUsageSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: codexDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexUsageError.codexDirectoryMissing(codexDirectory)
        }

        var latest: CodexUsageSnapshot?
        for fileURL in sessionLogFiles(in: codexDirectory) {
            if let snapshot = latestSnapshot(in: fileURL) {
                if latest == nil || snapshot.timestamp > latest!.timestamp {
                    latest = snapshot
                }
            }
        }

        guard let latest else {
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

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO8601 date: \(value)"
        )
    }

    private func sessionLogFiles(in codexDirectory: URL) -> [URL] {
        let roots = [
            codexDirectory.appendingPathComponent("sessions", isDirectory: true),
            codexDirectory.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        return roots.flatMap { root -> [URL] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return enumerator.compactMap { item -> URL? in
                guard let url = item as? URL, url.pathExtension == "jsonl" else {
                    return nil
                }
                return url
            }
        }
    }

    private func latestSnapshot(in fileURL: URL) -> CodexUsageSnapshot? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let contents = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        var latest: CodexUsageSnapshot?
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains(#""token_count""#), line.contains(#""rate_limits""#) else {
                continue
            }

            guard
                let lineData = line.data(using: .utf8),
                let event = try? decoder.decode(CodexEvent.self, from: lineData),
                let snapshot = event.snapshot
            else {
                continue
            }

            if latest == nil || snapshot.timestamp > latest!.timestamp {
                latest = snapshot
            }
        }

        return latest
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
