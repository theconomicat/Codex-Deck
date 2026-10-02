import Foundation
import Testing
@testable import CodexUsageWeb

@Test func httpParserWaitsForCompleteBody() throws {
    let head = "POST /api/pair HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nContent-Length: 2\r\n\r\n"
    #expect(try DeckHTTPRequest.parse(Data(head.utf8)) == nil)
    #expect(try DeckHTTPRequest.parse(Data((head + "{").utf8)) == nil)
    let request = try #require(try DeckHTTPRequest.parse(Data((head + "{}").utf8)))
    #expect(request.path == "/api/pair")
    #expect(request.body == Data("{}".utf8))
    #expect(request.headers["host"] == "127.0.0.1:8080")
}

@Test(arguments: [
    "GET / HTTP/1.1\r\nHost: local:8\r\nHost: evil:8\r\n\r\n",
    "POST /api/pair HTTP/1.1\r\nHost: local:8\r\nContent-Length: 2\r\ncontent-length: 2\r\n\r\n{}",
    "POST /api/pair HTTP/1.1\r\nHost: local:8\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n{}",
    "POST /api/pair HTTP/1.1\r\nHost: local:8\r\nContent-Length: +2\r\n\r\n{}",
    "POST /api/pair HTTP/1.1\r\nHost: local:8\r\nContent-Length: 2, 2\r\n\r\n{}",
    "POST /api/pair HTTP/1.1\r\nHost: local:8\r\nContent-Length: 999999999999999999999999\r\n\r\n",
    "POST /api/pair HTTP/1.1\r\nHost: local:8\r\n\r\n{}",
    "GET / HTTP/1.1\r\nHost: local:8\r\nContent-Length: 2\r\n\r\n{}",
    "GET / HTTP/1.1\r\nHost: local:8\r\n value: folded\r\n\r\n",
    "GET / HTTP/1.1\r\nHost : local:8\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: local:8\r\nX-Test: a\nb\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: local:8\r\nUpgrade: websocket\r\n\r\n",
    "GET / HTTP/1.1\r\n\r\n",
    "GET http://127.0.0.1/ HTTP/1.1\r\nHost: local:8\r\n\r\n",
    "GET / HTTP/1.0\r\nHost: local:8\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: local:8\r\n\r\nGET / HTTP/1.1\r\nHost: local:8\r\n\r\n"
]) func httpParserRejectsAmbiguousFraming(_ input: String) {
    #expect(throws: DeckHTTPError.self) { try DeckHTTPRequest.parse(Data(input.utf8)) }
}

@Test func httpParserBoundsMemoryAndHeaderSize() {
    #expect(throws: DeckHTTPError.self) { try DeckHTTPRequest.parse(Data(repeating: 65, count: 32_769)) }
    #expect(throws: DeckHTTPError.self) { try DeckHTTPRequest.parse(Data(repeating: 65, count: 8_193)) }
    let declared = "POST /api/pair HTTP/1.1\r\nHost: local:8\r\nContent-Length: 32768\r\n\r\n"
    #expect(throws: DeckHTTPError.self) { try DeckHTTPRequest.parse(Data(declared.utf8)) }
}

@Test func privateNetworkClassificationDoesNotAcceptAmbiguousOrPublicAddresses() {
    for ip in ["127.0.0.1", "10.0.1.7", "172.16.1.4", "172.31.255.1", "192.168.1.4"] {
        #expect(DeckNetwork.isPrivateIPv4(ip))
    }
    for ip in ["8.8.8.8", "0.0.0.0", "172.15.0.1", "172.32.0.1", "169.254.1.1", "192.168.1.256",
               "192.168.01.4", "192.168.1", "192.168..1", "2130706433", "localhost", "::1"] {
        #expect(!DeckNetwork.isPrivateIPv4(ip))
    }
}

@Test func responseIncludesSecurityHeadersAndExactLength() {
    let response = DeckHTTPResponse.json(["ok": true])
    let encoded = String(decoding: response.encoded(), as: UTF8.self)
    #expect(encoded.contains("Cache-Control: no-store\r\n"))
    #expect(encoded.contains("Content-Length: \(response.body.count)\r\n"))
    #expect(encoded.contains("Referrer-Policy: no-referrer\r\n"))
    #expect(encoded.contains("frame-ancestors 'none'"))
    #expect(!encoded.contains("Access-Control-Allow-Origin"))
}
