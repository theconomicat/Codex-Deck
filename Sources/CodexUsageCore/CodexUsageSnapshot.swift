import Foundation

public struct CodexUsageSnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let planType: String?
    public let limitID: String?

    public init(
        timestamp: Date,
        primary: UsageWindow?,
        secondary: UsageWindow?,
        planType: String?,
        limitID: String?
    ) {
        self.timestamp = timestamp
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.limitID = limitID
    }

    public var windows: [UsageWindow] {
        [primary, secondary].compactMap { $0 }.sorted { $0.windowMinutes < $1.windowMinutes }
    }
}

public struct UsageWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }

    public var label: String {
        if windowMinutes % 10080 == 0 { return "\(windowMinutes / 10080)w" }
        if windowMinutes % 1440 == 0 { return "\(windowMinutes / 1440)d" }
        if windowMinutes % 60 == 0 { return "\(windowMinutes / 60)h" }
        return "\(windowMinutes)m"
    }
}

public enum CodexUsageError: Error, LocalizedError {
    case codexDirectoryMissing(URL)
    case noUsageEventsFound(URL)

    public var errorDescription: String? {
        switch self {
        case .codexDirectoryMissing(let url):
            "Codex directory not found at \(url.path)"
        case .noUsageEventsFound(let url):
            "No Codex usage events found under \(url.path)"
        }
    }
}
