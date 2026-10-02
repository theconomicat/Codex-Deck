import Foundation
import Testing
@testable import CodexUsageWeb

@Test @MainActor func loopbackServerPairsAndDispatchesOnlyAnAuthenticatedFixturePreset() async throws {
    // This listener is loopback-only and every callback is an in-memory fixture.
    // It neither launches Codex nor connects to its debugging interface.
    let server = DeckServer(bindHost: "127.0.0.1")
    var applied: [Int] = []
    server.onState = { Data("{\"presets\":[{\"slot\":1}]}".utf8) }
    server.onPreset = { data in
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Int]
        if let slot = object?["slot"] { applied.append(slot) }
        return Data("{\"ok\":true}".utf8)
    }
    try await server.start()
    defer { server.stop() }
    #expect(server.isRunning)
    #expect(server.hosts == ["127.0.0.1"])
    #expect(server.pairingURL(host: "attacker.example") == nil)
    let pairing = try #require(server.pairingURL(host: "127.0.0.1"))
    let token = try #require(pairing.fragment?.replacingOccurrences(of: "pair=", with: ""))
    #expect(pairing.query == nil)
    let base = "http://127.0.0.1:\(server.port)"
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 5
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    let (_, home) = try await session.data(from: #require(URL(string: base + "/")))
    #expect((home as? HTTPURLResponse)?.statusCode == 200)
    let (_, denied) = try await session.data(from: #require(URL(string: base + "/api/state")))
    #expect((denied as? HTTPURLResponse)?.statusCode == 401)
    var pairRequest = URLRequest(url: try #require(URL(string: base + "/api/pair")))
    pairRequest.httpMethod = "POST"
    pairRequest.setValue(base, forHTTPHeaderField: "Origin")
    pairRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    pairRequest.httpBody = try JSONSerialization.data(withJSONObject: ["token": token])
    let (pairData, pairResponse) = try await session.data(for: pairRequest)
    let pairHTTP = try #require(pairResponse as? HTTPURLResponse)
    #expect(pairHTTP.statusCode == 200)
    let cookieHeader = try #require(pairHTTP.value(forHTTPHeaderField: "Set-Cookie"))
    #expect(cookieHeader.contains("HttpOnly"))
    #expect(cookieHeader.contains("SameSite=Strict"))
    let cookie = try #require(cookieHeader.components(separatedBy: ";").first)
    let pairJSON = try #require(try JSONSerialization.jsonObject(with: pairData) as? [String: String])
    let csrf = try #require(pairJSON["csrf"])
    #expect(server.connectedDeviceCount == 1)
    #expect(server.pairingURL(host: "127.0.0.1") == nil)
    var presetRequest = URLRequest(url: try #require(URL(string: base + "/api/preset")))
    presetRequest.httpMethod = "POST"
    presetRequest.setValue(base, forHTTPHeaderField: "Origin")
    presetRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    presetRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
    presetRequest.httpBody = Data("{\"slot\":1}".utf8)
    let (_, noCSRF) = try await session.data(for: presetRequest)
    #expect((noCSRF as? HTTPURLResponse)?.statusCode == 403)
    #expect(applied.isEmpty)
    presetRequest.setValue(csrf, forHTTPHeaderField: "X-Deck-CSRF")
    let (_, changed) = try await session.data(for: presetRequest)
    #expect((changed as? HTTPURLResponse)?.statusCode == 200)
    #expect(applied == [1])
    server.disconnectDevices()
    let (_, revoked) = try await session.data(for: presetRequest)
    #expect((revoked as? HTTPURLResponse)?.statusCode == 401)
    #expect(applied == [1])
    #expect(server.connectedDeviceCount == 0)
    #expect(server.pairingURL(host: "127.0.0.1") != nil)
    server.stop()
    #expect(!server.isRunning)
    #expect(server.port == 0)
    #expect(server.hosts.isEmpty)
    #expect(server.pairingExpiresAt == nil)
}

@Test @MainActor func serverRejectsPublicAndWildcardBindings() async {
    for host in ["0.0.0.0", "8.8.8.8", "::", "attacker.example"] {
        let server = DeckServer(bindHost: host)
        do {
            try await server.start()
            Issue.record("An unsafe bind address was accepted: \(host)")
            server.stop()
        } catch {
            #expect(!server.isRunning)
        }
    }
}
