import Foundation
import Testing
@testable import CodexUsageCore

@Test
func defaultPresetsMatchRequestedShortcuts() throws {
    let config = try PresetConfiguration.decode(PresetConfiguration.defaults.encoded())
    #expect(config.presets.map(\.slot) == [1, 2, 3, 4, 5])
    #expect(config.presets.map(\.model) == ["GPT-6 Astra", "GPT-6 Astra", "GPT-6 Astra", "GPT-6.1 Sol", "GPT-6.1 Sol"])
    #expect(config.presets.map(\.effort) == [.ultra, .xhigh, .high, .xhigh, .high])
    let example = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("presets.example.json")
    #expect(try PresetConfiguration.decode(Data(contentsOf: example)) == config)
    #expect(config.upgradingLegacyPresets() == config)
}

@Test func legacyDefaultsUpgradeToTheFiveRequestedPresets() throws {
    let json = #"{"version":1,"presets":[{"slot":3,"model":"GPT-6.1 Sol","effort":"high"},{"slot":1,"model":"GPT-6 Astra","effort":"xhigh"},{"slot":2,"model":"GPT-6.1 Sol","effort":"xhigh"}]}"#
    let old = try PresetConfiguration.decode(Data(json.utf8))
    let upgraded = old.upgradingLegacyPresets()
    #expect(upgraded == PresetConfiguration.defaults)
    #expect(upgraded.upgradingLegacyPresets() == upgraded)
}

@Test func legacyCustomModelsSurviveMigration() throws {
    let json = #"{"version":1,"presets":[{"slot":1,"model":"My Model","effort":"low"},{"slot":2,"model":"GPT-6 Astra","effort":"high"},{"slot":3,"model":"GPT-6.1 Sol","effort":"high"}]}"#
    let old = try PresetConfiguration.decode(Data(json.utf8))
    let upgraded = old.upgradingLegacyPresets()
    #expect(Array(upgraded.presets.prefix(3)) == old.presets)
    #expect(Array(upgraded.presets.suffix(2)) == Array(PresetConfiguration.defaults.presets.suffix(2)))
    #expect(try PresetConfiguration.decode(upgraded.encoded()) == upgraded)
}

@Test
func presetsAcceptUserModelsWithoutACodeChange() throws {
    let data = try PresetConfiguration.defaults.encoded()
    let edited = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "GPT-6 Astra", with: "My New Model")
    let config = try PresetConfiguration.decode(Data(edited.utf8))
    #expect(config.presets[0].model == "My New Model")
}

@Test(arguments: [
    #"{"version":2,"presets":[]}"#,
    #"{"version":1,"presets":[]}"#,
    #"{"version":1,"presets":[{"slot":1,"model":"A","effort":"high"},{"slot":1,"model":"B","effort":"high"},{"slot":3,"model":"C","effort":"high"}]}"#,
    #"{"version":1,"presets":[{"slot":1,"model":"A","effort":"extra high"},{"slot":2,"model":"B","effort":"high"},{"slot":3,"model":"C","effort":"high"}]}"#,
    #"{"version":1,"presets":[{"slot":1,"model":" ","effort":"high"},{"slot":2,"model":"B","effort":"high"},{"slot":3,"model":"C","effort":"high"}]}"#,
    #"{"version":1,"presets":[{"slot":1,"model":"A","effort":"high"},{"slot":2,"model":"B","effort":"high"},{"slot":3,"model":"C","effort":"high"},{"slot":4,"model":"D","effort":"high"}]}"#,
    #"{"version":1,"presets":[{"slot":1,"model":"A","effort":"high"},{"slot":2,"model":"B","effort":"high"},{"slot":3,"model":"C","effort":"high"},{"slot":4,"model":"D","effort":"high"},{"slot":4,"model":"E","effort":"high"}]}"#,
    #"{"version":1,"presets":[{"slot":1,"model":"A","effort":"high"},{"slot":2,"model":"B","effort":"high"},{"slot":3,"model":"C","effort":"high"},{"slot":4,"model":"D","effort":"high"},{"slot":6,"model":"E","effort":"high"}]}"#,
    "not json"
])
func invalidPresetsAreRejected(_ json: String) {
    #expect(throws: (any Error).self) { try PresetConfiguration.decode(Data(json.utf8)) }
}

@Test
func pickerMatchingDoesNotConfuseSimilarChoices() {
    #expect(PickerLabels.model("6.1 Sol", matches: "GPT-6.1 Sol"))
    #expect(!PickerLabels.model("GPT-6 Sol", matches: "GPT-6.1 Sol"))
    #expect(!PickerLabels.model("GPT-6 Astra preview", matches: "GPT-6 Astra"))
    #expect(!PickerLabels.model("GPT-6 Astra · High", matches: "GPT-6 Astra"))
    #expect(PickerLabels.effort("Extra high", matches: .xhigh))
    #expect(!PickerLabels.effort("Extra High", matches: .high))
    #expect(!PickerLabels.effort("High", matches: .xhigh))
    #expect(PickerLabels.combined("6.1 Sol Extra High", matches: PresetConfiguration.defaults.presets[3]))
    #expect(!PickerLabels.combined("6.1 Sol High", matches: PresetConfiguration.defaults.presets[3]))
}

@Test
func currentCodexPickerLabelsIncludeAnIntermediateModelListAndPowerControl() {
    #expect(PickerLabels.isModelListOpener("Select model"))
    #expect(PickerLabels.isModelListOpener("모델 선택"))
    #expect(!PickerLabels.isModelListOpener("Select effort"))
    #expect(PickerLabels.isPowerControl("Power"))
    #expect(PickerLabels.isPowerControl("파워"))
    #expect(PickerLabels.model("6 Astra", matches: "gpt-6-astra"))
    #expect(PickerLabels.model("6.1 Sol", matches: "gpt-6.1-sol"))
}

@Test
func powerAnnouncementConfirmsTheExactModelAndEffort() {
    // Codex 26.928's Power control describes its current selection and position.
    #expect(PickerLabels.selection(in: ["Power", "6.1 Sol Extra High, 4 of 6. Use Left and Right arrow keys to adjust power"], model: "GPT-6.1 Sol") == .xhigh)
    #expect(PickerLabels.selection(in: ["Select model", "6 Astra Extra High"], model: "GPT-6 Astra") == .xhigh)
    #expect(PickerLabels.selection(in: ["6.1 Sol High, 3 of 6."], model: "GPT-6.1 Sol") == .high)
    #expect(PickerLabels.selection(in: ["6.1 Sol Extended, 3 of 6."], model: "GPT-6.1 Sol") == .high)
    #expect(PickerLabels.selection(in: ["6.1 Sol Standard, 2 of 6."], model: "GPT-6.1 Sol") == .medium)
    #expect(PickerLabels.selection(in: ["6.1 Sol Light, 1 of 6."], model: "GPT-6.1 Sol") == .low)
    #expect(PickerLabels.selection(in: ["6.1 Sol 최대, 6개 중 5번째."], model: "GPT-6.1 Sol") == .max)
    #expect(PickerLabels.selection(in: ["6 Sol Extra High, 4 of 6."], model: "GPT-6.1 Sol") == nil)
    #expect(PickerLabels.selection(in: ["6.1 Sol High", "6.1 Sol Extra High"], model: "GPT-6.1 Sol") == nil)
    #expect(PickerLabels.selection(in: ["GPT-6.1 Sol preview High"], model: "GPT-6.1 Sol") == nil)
}

@Test func customButtonLabelsRoundTripWithoutChangingModelOrShortcut() throws {
    let data = try PresetConfiguration.defaults.encoded()
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var rows = try #require(object["presets"] as? [[String: Any]])
    rows[0]["label"] = "Focus"
    object["presets"] = rows
    let configuration = try PresetConfiguration.decode(JSONSerialization.data(withJSONObject: object))
    #expect(configuration.presets[0].label == "Focus")
    #expect(configuration.presets[0].model == "GPT-6 Astra")
    #expect(configuration.presets[0].effort == .ultra)
    #expect(configuration.presets[0].slot == 1)
    #expect(configuration.presets[1].label == nil)
    #expect(try PresetConfiguration.decode(configuration.encoded()) == configuration)
}

@Test(arguments: ["", " Focus", "Focus ", "Focus\nNow", "Focus\tNow", String(repeating: "x", count: 33)])
func malformedButtonLabelsKeepTheConfigurationInvalid(_ label: String) throws {
    var object = try #require(JSONSerialization.jsonObject(with: PresetConfiguration.defaults.encoded()) as? [String: Any])
    var rows = try #require(object["presets"] as? [[String: Any]])
    rows[0]["label"] = label
    object["presets"] = rows
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: PresetError.self) { try PresetConfiguration.decode(data) }
}
