import Foundation
import CodexUsageCore

public struct DirectSwitchResult: Codable, Sendable {
    public let model: String
    public let displayName: String
    public let effort: String
    public let changed: Bool
}

public struct DeckState: Codable, Sendable {
    public let targetID: String
    public let title: String
    public let model: String
    public let effort: String
    public let models: [DeckModel]?
    public let activity: String?
    public let dictation: DeckDictation?
    public let pending: [DeckPendingRequest]?
    public let pendingUnavailable: String?
}

public enum DirectSwitchError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let value): value } }
}

public struct DebugTarget: Codable, Sendable {
    public let type: String
    public let url: String
    public let webSocketDebuggerUrl: String?

    public static func mainWindow(in targets: [DebugTarget]) throws -> DebugTarget {
        let candidates = targets.filter {
            guard $0.type == "page", $0.webSocketDebuggerUrl != nil,
                  let url = URL(string: $0.url) else { return false }
            return url.scheme == "app" && url.path == "/index.html" &&
                !(url.query?.contains("initialRoute=") ?? false)
        }
        guard candidates.count == 1 else {
            throw DirectSwitchError.message("Open one main Codex window, then retry. The direct bridge could not identify a unique window.")
        }
        return candidates[0]
    }
}

public actor DirectModelSwitcher {
    private let port: Int
    private let session: URLSession
    private var busy = false

    public init(port: Int, session: URLSession = .shared) {
        self.port = port
        self.session = session
    }

    public static func validateResources() throws { _ = try scriptSource() }

    private static func scriptSource() throws -> String {
        let packagedBundle = Bundle.main.url(forResource: "Codex-Usage_CodexUsageAutomation", withExtension: "bundle")
            .flatMap { Bundle(url: $0) }
        guard let url = (packagedBundle ?? Bundle.module).url(forResource: "apply-preset", withExtension: "js") else {
            throw DirectSwitchError.message("The direct switching resource is missing. Reinstall Codex Deck.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func apply(_ preset: ModelPreset) async throws -> DirectSwitchResult {
        try await applyPreset(preset, targetID: nil)
    }

    /// Uses the same selection callback as a local preset, but requires the
    /// exact saved chat selected by the paired device instead of keyboard focus.
    public func applyRemote(_ preset: ModelPreset, targetID: String) async throws -> DirectSwitchResult {
        guard !targetID.isEmpty, targetID.count <= 512 else {
            throw DirectSwitchError.message("Select the current Codex chat in Web Deck first.")
        }
        return try await applyPreset(preset, targetID: targetID)
    }

    public func deckState() async throws -> DeckState {
        guard !busy else { throw DirectSwitchError.message("A model change is already in progress.") }
        busy = true
        defer { busy = false }
        let state: DeckState = try await evaluate(invocation: "readCodexDeck()")
        guard !state.targetID.isEmpty, !state.model.isEmpty, !state.effort.isEmpty else {
            throw DirectSwitchError.message("Codex did not expose a saved chat and its model selection.")
        }
        return state
    }

    public func control(_ input: DeckControlInput) async throws -> DeckControlResult {
        guard !busy else { throw DirectSwitchError.message("Another deck action is already in progress.") }
        busy = true
        defer { busy = false }
        // Revalidate callers as well as HTTP input. Never interpolate raw text into code.
        let data = try JSONEncoder().encode(input)
        _ = try DeckControlInput.validated(data)
        let json = String(decoding: data, as: UTF8.self)
        let result: DeckControlResult = try await evaluate(invocation: "performCodexDeckAction(\(json))")
        guard result.ok else { throw DirectSwitchError.message(result.message ?? "Codex did not confirm this action.") }
        return result
    }

    private func applyPreset(_ preset: ModelPreset, targetID: String?) async throws -> DirectSwitchResult {
        guard !busy else { throw DirectSwitchError.message("A model change is already in progress.") }
        busy = true
        defer { busy = false }
        let presetJSON = String(decoding: try JSONEncoder().encode(preset), as: UTF8.self)
        let invocation: String
        if let targetID {
            let targetJSON = String(decoding: try JSONEncoder().encode(targetID), as: UTF8.self)
            invocation = "applyCodexPreset(\(presetJSON), \(targetJSON))"
        } else {
            invocation = "applyCodexPreset(\(presetJSON))"
        }
        let confirmed: DirectSwitchResult = try await evaluate(invocation: invocation)
        guard (PickerLabels.model(confirmed.model, matches: preset.model) ||
               PickerLabels.model(confirmed.displayName, matches: preset.model)),
              confirmed.effort == preset.effort.rawValue else {
            throw DirectSwitchError.message("Codex returned a different model or effort.")
        }
        return confirmed
    }

    // Only the fixed operations above can invoke the loopback evaluator. No
    // expressions, CDP methods or URLs are accepted from a Web Deck request.
    private func evaluate<Result: Decodable & Sendable>(invocation: String) async throws -> Result {
        guard (1024...65535).contains(port) else { throw DirectSwitchError.message("Invalid direct bridge port.") }
        let url = URL(string: "http://127.0.0.1:\(port)/json/list")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let data: Data
        do {
            let response: URLResponse
            (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw DirectSwitchError.message("The direct bridge returned an unexpected response.")
            }
        } catch {
            throw DirectSwitchError.message("Open Codex Deck → Enable Direct Switching to restart Codex with its local bridge. \(error.localizedDescription)")
        }
        let target = try DebugTarget.mainWindow(in: JSONDecoder().decode([DebugTarget].self, from: data))
        guard let address = target.webSocketDebuggerUrl, let socketURL = URL(string: address),
              socketURL.scheme == "ws", socketURL.host == "127.0.0.1", socketURL.port == port,
              socketURL.user == nil, socketURL.password == nil else {
            throw DirectSwitchError.message("The direct bridge must stay on its configured local address.")
        }
        let source = try Self.scriptSource()
        let token = UUID().uuidString
        let expression = """
        (() => {
          const pending = globalThis.__codexUsagePending ??= new Map();
          const token = "\(token)";
          const promise = (async () => { \(source)
            return await \(invocation);
          })();
          pending.set(token, promise);
          setTimeout(() => pending.delete(token), 10000);
          promise.then(() => pending.delete(token), () => pending.delete(token));
          return promise;
        })()
        """
        let socket = session.webSocketTask(with: socketURL)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        return try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask {
                let message: [String: Any] = ["id": 1, "method": "Runtime.evaluate", "params": [
                    "expression": expression, "awaitPromise": true, "returnByValue": true
                ]]
                let json = try JSONSerialization.data(withJSONObject: message)
                try await socket.send(.string(String(decoding: json, as: UTF8.self)))
                while true {
                    let incoming = try await socket.receive()
                    let bytes: Data
                    switch incoming {
                    case .data(let value): bytes = value
                    case .string(let value): bytes = Data(value.utf8)
                    @unknown default: continue
                    }
                    guard let reply = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                          reply["id"] as? Int == 1 else { continue }
                    if let error = reply["error"] as? [String: Any] {
                        throw DirectSwitchError.message(error["message"] as? String ?? "The direct bridge rejected the request.")
                    }
                    guard let result = reply["result"] as? [String: Any] else {
                        throw DirectSwitchError.message("The direct bridge returned no result.")
                    }
                    if let exception = result["exceptionDetails"] as? [String: Any] {
                        let details = exception["exception"] as? [String: Any]
                        let description = details?["description"] as? String ?? exception["text"] as? String ?? "Codex rejected the preset."
                        var message = description.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .first { !$0.isEmpty } ?? "Codex rejected the preset."
                        if message.hasPrefix("Error:") {
                            message = String(message.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        }
                        throw DirectSwitchError.message(message.isEmpty ? "Codex rejected the preset." : message)
                    }
                    guard let value = (result["result"] as? [String: Any])?["value"] else {
                        throw DirectSwitchError.message("Codex did not return a confirmed preset.")
                    }
                    return try JSONDecoder().decode(Result.self, from: JSONSerialization.data(withJSONObject: value))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                socket.cancel(with: .goingAway, reason: nil)
                throw DirectSwitchError.message("The direct bridge request timed out. Check Codex before retrying.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
