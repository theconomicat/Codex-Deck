import CodexUsageCore
import Foundation

@MainActor
final class PresetStore {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Codex-Usage/presets.json")
    private(set) var configuration = PresetConfiguration.defaults
    private(set) var error: String?

    func reload() {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PresetConfiguration.defaults.encoded().write(to: url, options: .atomic)
            }
            let loaded = try PresetConfiguration.decode(Data(contentsOf: url))
            let upgraded = loaded.upgradingLegacyPresets()
            if upgraded != loaded {
                let backup = url.deletingLastPathComponent()
                    .appendingPathComponent("presets.before-five-slots-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: backup)
                try upgraded.encoded().write(to: url, options: .atomic)
            }
            configuration = upgraded
            error = nil
        } catch {
            self.error = "\(error.localizedDescription) Previous presets are still active."
        }
    }
}
