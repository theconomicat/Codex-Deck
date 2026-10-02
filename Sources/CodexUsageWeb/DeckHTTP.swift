import Foundation

public struct DeckHTTPError: LocalizedError, Sendable {
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    public var errorDescription: String? { message }
}

struct DeckHTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// One request per connection. No pipelining, chunking, folded headers, or duplicates.
    static func parse(_ data: Data) throws -> DeckHTTPRequest? {
        guard data.count <= 32_768 else {
            throw DeckHTTPError(status: 413, message: "Request is too large.")
        }
        guard let boundary = data.range(of: Data([13, 10, 13, 10])) else {
            if data.count > 8_192 { throw invalid("Headers are too large.") }
            return nil
        }
        guard boundary.lowerBound <= 8_192,
              let text = String(data: data[..<boundary.lowerBound], encoding: .ascii) else {
            throw invalid("Invalid headers.")
        }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2] == "HTTP/1.1",
              ["GET", "POST"].contains(String(first[0])),
              first[1].first == "/", first[1].utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              !first[1].contains("#"), !first[1].contains("?") else {
            throw invalid("Expected a supported HTTP/1.1 request.")
        }
        var headers: [String: String] = [:]
        let tokenCharacters = Set("!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw invalid("Invalid header.") }
            let name = String(line[..<colon])
            let raw = line[line.index(after: colon)...]
            guard !name.isEmpty, name.utf8.allSatisfy(tokenCharacters.contains),
                  raw.utf8.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 < 127) }) else {
                throw invalid("Invalid header.")
            }
            let key = name.lowercased()
            guard headers[key] == nil else { throw invalid("Duplicate headers are not supported.") }
            headers[key] = raw.trimmingCharacters(in: .whitespaces)
        }
        guard let host = headers["host"], !host.isEmpty,
              headers["transfer-encoding"] == nil, headers["expect"] == nil,
              headers["upgrade"] == nil else { throw invalid("Unsupported request framing.") }
        let length: Int
        if let value = headers["content-length"] {
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let parsed = Int(value), parsed <= 32_768 else {
                throw invalid("Invalid Content-Length.")
            }
            length = parsed
        } else {
            guard first[0] == "GET" else { throw invalid("Content-Length is required.") }
            length = 0
        }
        if first[0] == "GET", length != 0 { throw invalid("GET cannot contain a body.") }
        let end = boundary.upperBound + length
        guard end <= 32_768 else { throw DeckHTTPError(status: 413, message: "Request is too large.") }
        guard data.count <= end else { throw invalid("Multiple requests are not supported.") }
        guard data.count == end else { return nil }
        return DeckHTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers,
                               body: Data(data[boundary.upperBound..<end]))
    }

    private static func invalid(_ message: String) -> DeckHTTPError {
        DeckHTTPError(status: 400, message: message)
    }
}

struct DeckHTTPResponse: Sendable {
    var status: Int
    var body: Data
    var contentType = "application/json; charset=utf-8"
    var headers: [String: String] = [:]

    static func json(_ object: [String: Any], status: Int = 200) -> DeckHTTPResponse {
        DeckHTTPResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
    }

    static func error(_ status: Int, _ message: String) -> DeckHTTPResponse {
        .json(["error": message], status: status)
    }

    func encoded() -> Data {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 408: "Request Timeout",
                      409: "Conflict", 413: "Content Too Large", 415: "Unsupported Media Type",
                      429: "Too Many Requests", 500: "Internal Server Error", 503: "Service Unavailable"][status] ?? "Error"
        var fields = headers
        fields["Content-Type"] = contentType
        fields["Content-Length"] = String(body.count)
        fields["Connection"] = "close"
        fields["Cache-Control"] = "no-store"
        fields["X-Content-Type-Options"] = "nosniff"
        fields["Referrer-Policy"] = "no-referrer"
        fields["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
        var result = Data("HTTP/1.1 \(status) \(reason)\r\n".utf8)
        for key in fields.keys.sorted() { result.append(Data("\(key): \(fields[key]!)\r\n".utf8)) }
        result.append(Data("\r\n".utf8))
        result.append(body)
        return result
    }
}
