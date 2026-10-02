import CodexUsageCore
import CodexUsageWeb
import Foundation

/// Browser QA host. It has no automation dependency and never accesses Codex.
@main
struct WebDeckFixture {
    private struct PresetInput: Decodable {
        let slot: Int
        let targetID: String
        let model: String
        let effort: String
    }

    @MainActor
    static func main() async throws {
        let server = DeckServer(bindHost: "127.0.0.1")
        let presets = PresetConfiguration.defaults.presets
        var selection = presets[0]
        server.onState = {
            try JSONSerialization.data(withJSONObject: [
                "connected": true,
                "busy": false,
                "target": ["id": "fixture-chat", "title": "Fixture chat"],
                "selection": ["model": selection.model, "effort": selection.effort.rawValue],
                "presets": presets.map {
                    ["slot": $0.slot, "model": $0.model, "effort": $0.effort.rawValue, "title": $0.title] as [String: Any]
                },
                "usage": "Usage · 94% remaining · fixture data"
            ])
        }
        server.onPreset = { data in
            guard let input = try? JSONDecoder().decode(PresetInput.self, from: data),
                  let preset = presets.first(where: { $0.slot == input.slot }) else {
                throw DeckHTTPError(status: 400, message: "Choose one of the five fixture presets.")
            }
            guard input.targetID == "fixture-chat", input.model == preset.model,
                  input.effort == preset.effort.rawValue else {
                throw DeckHTTPError(status: 409, message: "The fixture target or preset does not match.")
            }
            selection = preset
            return try JSONSerialization.data(withJSONObject: ["ok": true, "message": "Applied \(preset.title) to Fixture chat."])
        }
        try await server.start()
        defer { server.stop() }
        guard let url = server.pairingURL(host: "127.0.0.1") else {
            throw DeckHTTPError(status: 503, message: "Fixture pairing URL unavailable.")
        }
        FileHandle.standardOutput.write(Data("Fixture only — no Codex connection.\n\(url.absoluteString)\n".utf8))
        // No polling or hidden control endpoints. Restart for a fresh pairing link.
        while !Task.isCancelled { try await Task.sleep(for: .seconds(3600)) }
    }
}
