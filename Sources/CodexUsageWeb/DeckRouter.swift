import CryptoKit
import Foundation
import Security

@MainActor
final class DeckRouter {
    struct Session {
        let csrf: String
        let expiresAt: Date
    }

    var allowedHosts: Set<String> = []
    var onState: (@MainActor () async throws -> Data)?
    var onPreset: (@MainActor (Data) async throws -> Data)?
    var onControl: (@MainActor (Data) async throws -> Data)?
    var onChange: (@MainActor () -> Void)?
    var staticAssets: [String: (Data, String)] = [:]
    private(set) var pairingToken: String?
    private(set) var pairingExpiresAt: Date?
    private var sessions: [String: Session] = [:]
    // Global failure budget prevents unbounded session/pairing work on the LAN.
    private var failedPairingTimes: [Date] = []

    var connectedDeviceCount: Int {
        sessions.values.filter { $0.expiresAt > Date() }.count
    }

    func rotatePairing(now: Date = Date()) {
        pairingToken = Self.randomToken()
        pairingExpiresAt = now.addingTimeInterval(300)
        failedPairingTimes.removeAll()
        onChange?()
    }

    func revokeAll() {
        sessions.removeAll()
        pairingToken = nil
        pairingExpiresAt = nil
        failedPairingTimes.removeAll()
        onChange?()
    }

    func route(_ request: DeckHTTPRequest, peer: String, now: Date = Date()) async -> DeckHTTPResponse {
        guard DeckNetwork.isPrivateIPv4(peer) else { return .error(403, "Only local network devices are allowed.") }
        guard let host = request.headers["host"], allowedHosts.contains(host.lowercased()) else {
            return .error(403, "This host is not allowed.")
        }
        if let origin = request.headers["origin"], origin != "http://\(host.lowercased())" {
            return .error(403, "Cross-origin requests are not allowed.")
        }
        if let site = request.headers["sec-fetch-site"], !["same-origin", "none"].contains(site) {
            return .error(403, "Cross-origin requests are not allowed.")
        }
        if request.method == "GET", let asset = staticAssets[request.path] {
            return DeckHTTPResponse(status: 200, body: asset.0, contentType: asset.1)
        }
        let routes = ["/api/state": "GET", "/api/pair": "POST", "/api/preset": "POST", "/api/control": "POST", "/api/logout": "POST"]
        guard let method = routes[request.path] else { return .error(404, "Route not found.") }
        guard request.method == method else { return .error(405, "Method not allowed.") }
        if request.method == "POST" {
            guard request.headers["origin"] == "http://\(host.lowercased())" else {
                return .error(403, "A same-origin request is required.")
            }
            guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
                return .error(415, "Expected application/json.")
            }
            guard (try? JSONSerialization.jsonObject(with: request.body)) is [String: Any] else {
                return .error(400, "Expected a JSON object.")
            }
        }
        if request.path == "/api/pair" { return pair(request, now: now) }

        sessions = sessions.filter { $0.value.expiresAt > now }
        guard let key = sessionKey(from: request), let session = sessions[key] else {
            return .error(401, "Pair this device with Codex Deck first.")
        }
        if request.method == "POST" {
            guard let csrf = request.headers["x-deck-csrf"], Self.constantTimeEqual(csrf, session.csrf) else {
                return .error(403, "The request token is missing or invalid.")
            }
        }
        if request.path == "/api/logout" {
            sessions.removeValue(forKey: key)
            onChange?()
            var response = DeckHTTPResponse.json(["ok": true])
            response.headers["Set-Cookie"] = "codexDeckSession=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0"
            return response
        }
        do {
            let body: Data
            switch request.path {
            case "/api/state":
                guard let handler = onState else { return .error(503, "The deck is not ready.") }
                body = try await handler()
            case "/api/preset":
                guard let handler = onPreset else { return .error(503, "Model switching is not available.") }
                body = try await handler(request.body)
            case "/api/control":
                guard let handler = onControl else { return .error(503, "Deck controls are not available.") }
                body = try await handler(request.body)
            default:
                return .error(404, "Route not found.")
            }
            // Disabling the server/revoking a phone while an async handler runs must
            // not hand the old session a newly returned conversation snapshot.
            guard let remaining = sessions[key], remaining.expiresAt > Date() else {
                return .error(401, "This device has been disconnected.")
            }
            guard var value = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return .error(500, "The deck returned an invalid response.")
            }
            if request.path == "/api/state" { value["csrf"] = session.csrf }
            return .json(value)
        } catch let error as DeckHTTPError {
            return .error((400...599).contains(error.status) ? error.status : 500, error.message)
        } catch {
            return .error(503, error.localizedDescription)
        }
    }

    private func pair(_ request: DeckHTTPRequest, now: Date) -> DeckHTTPResponse {
        failedPairingTimes = failedPairingTimes.filter { now.timeIntervalSince($0) < 60 }
        guard failedPairingTimes.count < 10 else { return .error(429, "Too many pairing attempts. Try again in a minute.") }
        guard let value = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              value.count == 1, let token = value["token"] as? String,
              let expected = pairingToken, let deadline = pairingExpiresAt, deadline > now,
              Self.constantTimeEqual(token, expected) else {
            failedPairingTimes.append(now)
            return .error(401, "Pairing link expired or already used. Create a new link on your Mac.")
        }
        sessions = sessions.filter { $0.value.expiresAt > now }
        guard sessions.count < 8 else { return .error(409, "Disconnect devices on your Mac before pairing another.") }
        pairingToken = nil
        pairingExpiresAt = nil
        let credential = Self.randomToken()
        let csrf = Self.randomToken()
        sessions[Self.digest(credential)] = Session(csrf: csrf, expiresAt: now.addingTimeInterval(8 * 3600))
        onChange?()
        var response = DeckHTTPResponse.json(["csrf": csrf])
        response.headers["Set-Cookie"] = "codexDeckSession=\(credential); Path=/; HttpOnly; SameSite=Strict; Max-Age=28800"
        return response
    }

    private func sessionKey(from request: DeckHTTPRequest) -> String? {
        guard let cookie = request.headers["cookie"] else { return nil }
        var credentials: [String] = []
        for part in cookie.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.first == "codexDeckSession", pair.count == 2 { credentials.append(String(pair[1])) }
        }
        guard credentials.count == 1, credentials[0].count == 64 else { return nil }
        return Self.digest(credentials[0])
    }

    private static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ first: String, _ second: String) -> Bool {
        let left = SHA256.hash(data: Data(first.utf8))
        let right = SHA256.hash(data: Data(second.utf8))
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess,
                     "Secure randomness is unavailable.")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
