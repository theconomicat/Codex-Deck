import CodexUsageCore
import Foundation

enum SnapshotFormatter {
    static func menuLine(_ window: UsageWindow, showWindowLabel: Bool = false, now: Date = Date()) -> String {
        let label = showWindowLabel ? "Usage (\(window.label))" : "Usage"
        if window.isExpired(at: now) { return "\(label) · -- · awaiting a new Codex usage event" }
        let percent = Int(window.remainingPercent.rounded())
        let reset = window.resetsAt.map { "reset in \(duration($0.timeIntervalSince(now)))" } ?? "reset time unavailable"
        return "\(label) · \(percent)% remaining · \(reset)"
    }

    static func textSummary(_ snapshot: CodexUsageSnapshot) -> String {
        let lines = snapshot.windows.isEmpty ? ["No quota windows reported"] : snapshot.windows.map { menuLine($0, showWindowLabel: snapshot.windows.count > 1) }
        return (lines + ["Data as of \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))"]).joined(separator: "\n")
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
