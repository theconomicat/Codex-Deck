import AppKit

@MainActor
enum AppInstallation {
    static let destination = URL(fileURLWithPath: "/Applications/Codex Deck.app", isDirectory: true)

    /// Keep setup attached to the canonical installed copy.
    static func installForDirectSwitching() async throws -> Bool {
        let source = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard source != destination else { return false }
        let manager = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".Codex Deck-\(UUID().uuidString).app", isDirectory: true)
        try manager.copyItem(at: source, to: staging)
        defer { try? manager.removeItem(at: staging) }
        if manager.fileExists(atPath: destination.path) {
            guard Bundle(url: destination)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw NSError(domain: "CodexUsage.Installation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Another app occupies \(destination.path). Move it before installing Codex Deck."])
            }
            for app in NSWorkspace.shared.runningApplications where app.bundleURL == destination {
                app.terminate()
            }
            // Keep the previous copy recoverable in the Trash.
            try manager.trashItem(at: destination, resultingItemURL: nil)
        }
        try manager.moveItem(at: staging, to: destination)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--setup-direct-switching"]
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
        NSApp.terminate(nil)
        return true
    }
}
