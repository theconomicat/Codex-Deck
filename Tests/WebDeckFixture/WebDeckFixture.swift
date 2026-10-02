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
        var selectedModel = presets[0].model
        var selectedEffort = presets[0].effort.rawValue
        var recording = false
        let models: [[String: Any]] = [
            ["id": "GPT-6 Astra", "name": "GPT-6 Astra", "efforts": ["low", "medium", "high", "xhigh", "ultra"]],
            ["id": "GPT-6.1 Sol", "name": "GPT-6.1 Sol", "efforts": ["low", "medium", "high", "xhigh"]]
        ]
        var pending: [[String: Any]] = [
            ["id": "fixture-approval", "fingerprint": "fixture-approval-v1", "kind": "approval",
             "title": "Allow this fixture command?", "detail": "swift test (simulation only)",
             "choices": [["id": "approve", "label": "Allow once"], ["id": "deny", "label": "Deny"]]],
            ["id": "fixture-question", "fingerprint": "fixture-question-v1", "kind": "question",
             "title": "Fixture question", "questions": [["id": "approach", "prompt": "Which approach should the fixture use?",
                "allowOther": true, "isSecret": false, "options": [["id": "Small change", "label": "Small change"],
                                                                    ["id": "Research first", "label": "Research first"]]]]]
        ]
        server.onState = {
            try JSONSerialization.data(withJSONObject: [
                "connected": true,
                "busy": false,
                "target": ["id": "fixture-chat", "title": "Fixture chat"],
                "selection": ["model": selectedModel, "effort": selectedEffort],
                "models": models,
                "dictation": ["available": true, "recording": recording, "owned": recording],
                "pending": pending,
                "presets": presets.map {
                    ["slot": $0.slot, "model": $0.model, "effort": $0.effort.rawValue, "title": $0.title] as [String: Any]
                },
                "usage": "Usage · 94% remaining · fixture data",
                "usageMeter": ["remainingPercent": 94]
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
            selectedModel = preset.model
            selectedEffort = preset.effort.rawValue
            return try JSONSerialization.data(withJSONObject: ["ok": true, "message": "Applied \(preset.title) to Fixture chat."])
        }
        server.onControl = { data in
            guard let input = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  input["targetID"] as? String == "fixture-chat" else {
                throw DeckHTTPError(status: 409, message: "The fixture target changed.")
            }
            switch input["type"] as? String {
            case "model":
                guard let model = models.first(where: { $0["id"] as? String == input["model"] as? String }),
                      let effort = input["effort"] as? String, (model["efforts"] as? [String])?.contains(effort) == true else {
                    throw DeckHTTPError(status: 400, message: "Choose a supported fixture model and effort.")
                }
                selectedModel = model["id"] as! String
                selectedEffort = effort
            case "dictation":
                guard let requested = input["recording"] as? Bool else { throw DeckHTTPError(status: 400, message: "Choose a microphone state.") }
                recording = requested // Simulation; never access a real microphone.
            case "approval", "question":
                guard let index = pending.firstIndex(where: { $0["id"] as? String == input["id"] as? String &&
                    $0["fingerprint"] as? String == input["fingerprint"] as? String }) else {
                    throw DeckHTTPError(status: 409, message: "The fixture request changed.")
                }
                pending.remove(at: index) // No command or message is executed.
            default: throw DeckHTTPError(status: 400, message: "Unsupported fixture action.")
            }
            return try JSONSerialization.data(withJSONObject: ["ok": true, "message": "Fixture action confirmed."])
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
