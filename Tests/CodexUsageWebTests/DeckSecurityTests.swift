import Foundation
import Testing
@testable import CodexUsageWeb

@MainActor
private func fixtureRouter() -> DeckRouter {
    let router = DeckRouter()
    router.allowedHosts = ["192.168.1.10:8000"]
    router.staticAssets = ["/": (Data("<html>Fixture</html>".utf8), "text/html")]
    router.onState = { Data("{\"presets\":[],\"csrf\":\"cannot-override-session\"}".utf8) }
    router.onPreset = { _ in Data("{\"ok\":true}".utf8) }
    router.rotatePairing()
    return router
}

private func request(_ path: String, method: String = "GET", body: [String: String] = [:],
                     cookie: String? = nil, csrf: String? = nil,
                     headers extra: [String: String] = [:]) throws -> DeckHTTPRequest {
    var headers = ["host": "192.168.1.10:8000"]
    if method == "POST" {
        headers["origin"] = "http://192.168.1.10:8000"
        headers["content-type"] = "application/json"
    }
    if let cookie { headers["cookie"] = cookie }
    if let csrf { headers["x-deck-csrf"] = csrf }
    headers.merge(extra) { _, new in new }
    return DeckHTTPRequest(method: method, path: path, headers: headers,
                           body: try JSONSerialization.data(withJSONObject: body))
}

@MainActor
private func pair(_ router: DeckRouter, now: Date = Date()) async throws -> (String, String) {
    let response = await router.route(try request("/api/pair", method: "POST", body: ["token": try #require(router.pairingToken)]),
                                      peer: "192.168.1.20", now: now)
    #expect(response.status == 200)
    let cookie = try #require(response.headers["Set-Cookie"]?.components(separatedBy: ";").first)
    let object = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: String])
    return (cookie, try #require(object["csrf"]))
}

@Test @MainActor func pairingIsOneTimeAndSessionRequiresCSRF() async throws {
    let router = fixtureRouter()
    let originalToken = try #require(router.pairingToken)
    #expect(originalToken.count == 64)
    #expect(await router.route(try request("/api/state"), peer: "192.168.1.20").status == 401)
    let (cookie, csrf) = try await pair(router)
    #expect(router.connectedDeviceCount == 1)
    #expect(router.pairingToken == nil)
    #expect(await router.route(try request("/api/pair", method: "POST", body: ["token": originalToken]), peer: "192.168.1.20").status == 401)
    let state = await router.route(try request("/api/state", cookie: cookie), peer: "192.168.1.20")
    #expect(state.status == 200)
    let stateJSON = try #require(try JSONSerialization.jsonObject(with: state.body) as? [String: Any])
    #expect(stateJSON["csrf"] as? String == csrf)
    #expect(await router.route(try request("/api/preset", method: "POST", cookie: cookie), peer: "192.168.1.20").status == 403)
    #expect(await router.route(try request("/api/preset", method: "POST", cookie: cookie, csrf: "incorrect"), peer: "192.168.1.20").status == 403)
    #expect(await router.route(try request("/api/preset", method: "POST", cookie: cookie, csrf: csrf), peer: "192.168.1.20").status == 200)
    #expect(await router.route(try request("/api/state", cookie: cookie + "; " + cookie), peer: "192.168.1.20").status == 401)
}

@Test @MainActor func untrustedHostsOriginsAndPublicPeersCannotUsePairing() async throws {
    let router = fixtureRouter()
    let token = try #require(router.pairingToken)
    for headers in [["host": "attacker.example:8000"], ["origin": "http://attacker.example"],
                    ["origin": "null"], ["origin": ""], ["sec-fetch-site": "cross-site"],
                    ["sec-fetch-site": "same-site"], ["host": "192.168.1.10"]] {
        #expect(await router.route(try request("/api/pair", method: "POST", body: ["token": token], headers: headers),
                                   peer: "192.168.1.20").status == 403)
    }
    #expect(await router.route(try request("/api/pair", method: "POST", body: ["token": token]), peer: "8.8.8.8").status == 403)
    #expect(router.connectedDeviceCount == 0)
    _ = try await pair(router)
}

@Test @MainActor func pairingExpiresAndRateLimitsGuessing() async throws {
    let router = fixtureRouter()
    let now = Date()
    router.rotatePairing(now: now)
    #expect(await router.route(try request("/api/pair", method: "POST", body: ["token": try #require(router.pairingToken)]),
                               peer: "192.168.1.20", now: now.addingTimeInterval(301)).status == 401)
    router.rotatePairing(now: now)
    for _ in 0..<10 {
        #expect(await router.route(try request("/api/pair", method: "POST", body: ["token": "wrong"]),
                                   peer: "192.168.1.20", now: now).status == 401)
    }
    #expect(await router.route(try request("/api/pair", method: "POST", body: ["token": try #require(router.pairingToken)]),
                               peer: "192.168.1.20", now: now).status == 429)
    _ = try await pair(router, now: now.addingTimeInterval(61))
}

@Test @MainActor func logoutExpiryAndRevocationInvalidateSessions() async throws {
    let router = fixtureRouter()
    let (cookie, csrf) = try await pair(router)
    let loggedOut = await router.route(try request("/api/logout", method: "POST", cookie: cookie, csrf: csrf), peer: "192.168.1.20")
    #expect(loggedOut.status == 200)
    #expect(loggedOut.headers["Set-Cookie"]?.contains("Max-Age=0") == true)
    #expect(await router.route(try request("/api/state", cookie: cookie), peer: "192.168.1.20").status == 401)
    router.rotatePairing()
    let (secondCookie, _) = try await pair(router)
    #expect(await router.route(try request("/api/state", cookie: secondCookie), peer: "192.168.1.20",
                               now: Date().addingTimeInterval(8 * 3600 + 1)).status == 401)
    router.rotatePairing()
    let (thirdCookie, _) = try await pair(router)
    router.revokeAll()
    #expect(router.connectedDeviceCount == 0)
    #expect(await router.route(try request("/api/state", cookie: thirdCookie), peer: "192.168.1.20").status == 401)
}

@Test @MainActor func onlyKnownRoutesAndJSONMutationsAreAccepted() async throws {
    let router = fixtureRouter()
    #expect(await router.route(try request("/"), peer: "192.168.1.20").status == 200)
    for path in ["/api/respond", "/json/list", "/api/evaluate", "/../Package.swift", "/%2e%2e/Package.swift"] {
        #expect(await router.route(try request(path), peer: "192.168.1.20").status == 404)
    }
    #expect(await router.route(try request("/api/pair"), peer: "192.168.1.20").status == 405)
    #expect(await router.route(try request("/api/pair", method: "POST", headers: ["content-type": "text/plain"]), peer: "192.168.1.20").status == 415)
    let arrayBody = DeckHTTPRequest(method: "POST", path: "/api/pair",
                                    headers: ["host": "192.168.1.10:8000", "origin": "http://192.168.1.10:8000", "content-type": "application/json"],
                                    body: Data("[]".utf8))
    #expect(await router.route(arrayBody, peer: "192.168.1.20").status == 400)
    let (cookie, csrf) = try await pair(router)
    router.onPreset = { _ in throw DeckHTTPError(status: 409, message: "The active chat changed.") }
    #expect(await router.route(try request("/api/preset", method: "POST", cookie: cookie, csrf: csrf), peer: "192.168.1.20").status == 409)
    router.onPreset = nil
    #expect(await router.route(try request("/api/preset", method: "POST", cookie: cookie, csrf: csrf), peer: "192.168.1.20").status == 503)
}

@Test @MainActor func pairingSessionLimitBoundsMemory() async throws {
    let router = fixtureRouter()
    for _ in 0..<8 {
        router.rotatePairing()
        _ = try await pair(router)
    }
    router.rotatePairing()
    #expect(await router.route(try request("/api/pair", method: "POST", body: ["token": try #require(router.pairingToken)]), peer: "192.168.1.20").status == 409)
    #expect(router.connectedDeviceCount == 8)
}
