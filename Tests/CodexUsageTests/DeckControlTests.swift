import Foundation
import Testing
@testable import CodexUsageAutomation

@Test func deckControlAcceptsOnlySpecificTypedActions() throws {
    for json in [
        #"{"type":"model","targetID":"chat-1","model":"gpt-6-astra","effort":"ultra"}"#,
        #"{"type":"dictation","targetID":"chat-1","recording":true}"#,
        #"{"type":"approval","targetID":"chat-1","id":"exec:1","fingerprint":"snapshot","decision":"approve"}"#,
        #"{"type":"approval","targetID":"chat-1","id":"exec:1","fingerprint":"snapshot","decision":"deny"}"#,
        #"{"type":"question","targetID":"chat-1","id":"question:1","fingerprint":"snapshot","answers":[{"id":"q1","optionID":"One"},{"id":"q2","text":"A detailed answer"}]}"#
    ] {
        let input = try DeckControlInput.validated(Data(json.utf8))
        #expect(input.targetID == "chat-1")
        _ = try DeckControlInput.validated(JSONEncoder().encode(input))
    }
}

@Test func deckControlRejectsGenericExecutionBlanketApprovalAndMalformedAnswers() {
    for json in [
        #"{"type":"eval","targetID":"chat-1","expression":"anything"}"#,
        #"{"type":"message","targetID":"chat-1","text":"arbitrary prompt"}"#,
        #"{"type":"approval","targetID":"chat-1","id":"exec:1","fingerprint":"snapshot","decision":"acceptForSession"}"#,
        #"{"type":"approval","targetID":"chat-1","id":"exec:1","decision":"approve"}"#,
        #"{"type":"dictation","targetID":"chat-1","recording":1}"#,
        #"{"type":"dictation","targetID":"","recording":true}"#,
        #"{"type":"model","targetID":"chat-1","model":"m","effort":"high","expression":"anything"}"#,
        #"{"type":"model","targetID":"chat-1","model":"m","effort":"unlimited"}"#,
        #"{"type":"question","targetID":"chat-1","id":"q","fingerprint":"s","answers":[]}"#,
        #"{"type":"question","targetID":"chat-1","id":"q","fingerprint":"s","answers":[{"id":"q1","text":" "}]}"#,
        #"{"type":"question","targetID":"chat-1","id":"q","fingerprint":"s","answers":[{"id":"q1","text":"one"},{"id":"q1","text":"two"}]}"#,
        #"{"type":"question","targetID":"chat-1","id":"q","fingerprint":"s","answers":[{"id":"q1","text":"one","execute":true}]}"#
    ] {
        #expect(throws: (any Error).self) { try DeckControlInput.validated(Data(json.utf8)) }
    }
}

@Test func deckControlBoundsUTF8PayloadWithoutChangingUserText() throws {
    let json: [String: Any] = ["type": "question", "targetID": "chat-1", "id": "q", "fingerprint": "snapshot",
                               "answers": [["id": "q1", "text": "quoted \"value\"\nnext line"]]]
    let input = try DeckControlInput.validated(JSONSerialization.data(withJSONObject: json))
    #expect(input.answers?.first?.text == "quoted \"value\"\nnext line")
    var oversized = json
    oversized["answers"] = [["id": "q1", "text": String(repeating: "x", count: 8001)]]
    #expect(throws: (any Error).self) { try DeckControlInput.validated(JSONSerialization.data(withJSONObject: oversized)) }
}
