import Foundation
import CodexUsageCore

public struct DeckModel: Codable, Sendable {
    public let id: String
    public let name: String
    public let efforts: [String]
}

public struct DeckDictation: Codable, Sendable {
    public let available: Bool
    public let recording: Bool
    public let owned: Bool?
}

public struct DeckChoice: Codable, Sendable {
    public let id: String
    public let label: String
    public let description: String?
}

public struct DeckQuestion: Codable, Sendable {
    public let id: String
    public let prompt: String
    public let isSecret: Bool?
    public let allowOther: Bool
    public let options: [DeckChoice]
}

public struct DeckPendingRequest: Codable, Sendable {
    public let id: String
    public let fingerprint: String
    public let kind: String
    public let title: String
    public let detail: String?
    public let choices: [DeckChoice]?
    public let questions: [DeckQuestion]?
}

/// JSON data only. Unknown keys and action types never reach the evaluator.
public struct DeckControlInput: Codable, Sendable {
    public struct Answer: Codable, Sendable {
        public let id: String
        public let optionID: String?
        public let text: String?
    }
    public let type: String
    public let targetID: String
    public let model: String?
    public let effort: String?
    public let recording: Bool?
    public let id: String?
    public let fingerprint: String?
    public let decision: String?
    public let answers: [Answer]?

    public static func validated(_ data: Data) throws -> Self {
        func reject() -> DirectSwitchError { .message("The deck control request is invalid. Refresh and try again.") }
        guard data.count <= 32 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let input = try? JSONDecoder().decode(Self.self, from: data),
              !input.targetID.isEmpty, input.targetID.utf8.count <= 512 else { throw reject() }
        let expectedKeys: Set<String>
        switch input.type {
        case "model":
            expectedKeys = ["type", "targetID", "model", "effort"]
            guard let model = input.model, !model.isEmpty, model.utf8.count <= 200,
                  let effort = input.effort, ReasoningEffort(rawValue: effort) != nil else { throw reject() }
        case "dictation":
            expectedKeys = ["type", "targetID", "recording"]
            guard input.recording != nil else { throw reject() }
        case "approval", "question":
            guard let id = input.id, !id.isEmpty, id.utf8.count <= 512,
                  let fingerprint = input.fingerprint, !fingerprint.isEmpty,
                  fingerprint.utf8.count <= 12 * 1024 else { throw reject() }
            if input.type == "approval" {
                expectedKeys = ["type", "targetID", "id", "fingerprint", "decision"]
                guard input.decision == "approve" || input.decision == "deny" else { throw reject() }
            } else {
                expectedKeys = ["type", "targetID", "id", "fingerprint", "answers"]
                guard let answers = input.answers, !answers.isEmpty, answers.count <= 12,
                      Set(answers.map(\.id)).count == answers.count,
                      let rawAnswers = object["answers"] as? [[String: Any]] else { throw reject() }
                for (answer, raw) in zip(answers, rawAnswers) {
                    guard !answer.id.isEmpty, answer.id.utf8.count <= 512,
                          Set(raw.keys).isSubset(of: ["id", "optionID", "text"]),
                          (answer.optionID?.utf8.count ?? 0) <= 4096,
                          (answer.text?.utf8.count ?? 0) <= 8000,
                          !(answer.optionID?.isEmpty ?? true) || !(answer.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    else { throw reject() }
                }
            }
        default: throw reject()
        }
        guard Set(object.keys) == expectedKeys else { throw reject() }
        return input
    }
}

public struct DeckControlResult: Codable, Sendable {
    public let ok: Bool
    public let message: String?
}
