import Foundation

public struct ModelPreset: Codable, Equatable, Sendable {
    public let slot: Int
    public let model: String
    public let effort: ReasoningEffort

    public var title: String { "\(model) · \(effort.title)" }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
    case none, minimal, low, medium, high, xhigh, max, ultra

    public var title: String {
        self == .xhigh ? "Extra High" : rawValue.capitalized
    }
}

public struct PresetConfiguration: Codable, Equatable, Sendable {
    public let version: Int
    public let presets: [ModelPreset]

    public static let defaults = PresetConfiguration(version: 1, presets: [
        ModelPreset(slot: 1, model: "GPT-6 Astra", effort: .ultra),
        ModelPreset(slot: 2, model: "GPT-6 Astra", effort: .xhigh),
        ModelPreset(slot: 3, model: "GPT-6 Astra", effort: .high),
        ModelPreset(slot: 4, model: "GPT-6.1 Sol", effort: .xhigh),
        ModelPreset(slot: 5, model: "GPT-6.1 Sol", effort: .high)
    ])

    public static func decode(_ data: Data) throws -> PresetConfiguration {
        let config: Self
        do {
            config = try JSONDecoder().decode(Self.self, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            let field = context.codingPath.map(\.stringValue).joined(separator: ".")
            if context.codingPath.last?.stringValue == "effort" {
                throw PresetError.invalid("\(field): use none, minimal, low, medium, high, xhigh, max, or ultra. Extra High is xhigh.")
            }
            throw PresetError.invalid("\(field.isEmpty ? "JSON" : field): \(context.debugDescription)")
        }
        guard config.version == 1 else { throw PresetError.invalid("version must be 1.") }
        let slots = Set(config.presets.map(\.slot))
        guard (config.presets.count == 5 && slots == Set(1...5)) ||
              (config.presets.count == 3 && slots == Set(1...3)) else {
            throw PresetError.invalid("Provide slots 1 through 5 exactly once. Legacy files with slots 1, 2, and 3 are upgraded automatically.")
        }
        for preset in config.presets {
            guard !preset.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  preset.model.count <= 120, !PickerLabels.normalized(preset.model).isEmpty,
                  !preset.model.contains(where: { $0.isNewline }),
                  preset.model == preset.model.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw PresetError.invalid("Slot \(preset.slot): model must be a nonempty menu label without surrounding spaces or line breaks.")
            }
        }
        return config
    }

    public func upgradingLegacyPresets() -> Self {
        guard presets.count == 3 else { return self }
        let previousDefaults = [
            ModelPreset(slot: 1, model: "GPT-6 Astra", effort: .xhigh),
            ModelPreset(slot: 2, model: "GPT-6.1 Sol", effort: .xhigh),
            ModelPreset(slot: 3, model: "GPT-6.1 Sol", effort: .high)
        ]
        if presets.sorted(by: { $0.slot < $1.slot }) == previousDefaults { return Self.defaults }
        return Self(version: version, presets: presets + Self.defaults.presets.filter { $0.slot > 3 })
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

public enum PresetError: LocalizedError {
    case invalid(String)

    public var errorDescription: String? {
        switch self { case .invalid(let message): "Invalid presets.json: \(message)" }
    }
}

/// Matching is deliberately exact after normalization, so similarly named models
/// and effort levels (High / Extra High) cannot silently select one another.
public enum PickerLabels {
    public static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    public static func model(_ label: String, matches model: String) -> Bool {
        modelKey(label) == modelKey(model)
    }

    public static func effort(_ label: String, matches effort: ReasoningEffort) -> Bool {
        effortLabels(effort).contains { normalized(label) == normalized($0) }
    }

    public static func combined(_ label: String, matches preset: ModelPreset) -> Bool {
        effortLabels(preset.effort).contains { modelKey(label) == modelKey(preset.model + $0) }
    }

    public static func isModelListOpener(_ label: String) -> Bool {
        ["selectmodel", "모델선택"].contains(normalized(label))
    }

    public static func isPowerControl(_ label: String) -> Bool {
        ["power", "파워"].contains(normalized(label))
    }

    public static func isPickerTrigger(_ label: String) -> Bool {
        isModelListOpener(label) || ["selecteffort", "추론수준선택"].contains(normalized(label))
    }

    /// The current picker describes Power as "{model} {effort}, {position} of {total}."
    /// Only the complete selection before that comma is matched, never a substring.
    public static func selection(in labels: [String], model: String) -> ReasoningEffort? {
        let matches = ReasoningEffort.allCases.filter { effort in
            labels.contains { label in
                let value = String(label.split(separator: ",", maxSplits: 1).first ?? "")
                return combined(value, matches: ModelPreset(slot: 1, model: model, effort: effort))
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func effortLabels(_ effort: ReasoningEffort) -> [String] {
        var labels = [effort.title, effort.rawValue]
        // Labels shipped in the English and Korean Codex model picker.
        if effort == .low { labels.append("Light") }
        if effort == .medium { labels.append("Standard") }
        if effort == .high { labels.append("Extended") }
        if effort == .max { labels.append("최대") }
        return labels
    }

    private static func modelKey(_ value: String) -> String {
        let value = normalized(value)
        return value.hasPrefix("gpt") ? String(value.dropFirst(3)) : value
    }
}
