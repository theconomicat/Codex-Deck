import Darwin
import Foundation

enum DeckNetwork {
    static func isPrivateIPv4(_ address: String) -> Bool {
        let pieces = address.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return false }
        let octets = pieces.compactMap { piece -> Int? in
            guard !piece.isEmpty, piece.utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = Int(piece), (0...255).contains(value), String(value) == piece else { return nil }
            return value
        }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || octets[0] == 127 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
    }

    static func localIPv4Addresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var values: [(String, String)] = []
        var cursor = interfaces
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let entry = current.pointee
            let name = String(cString: entry.ifa_name)
            guard (name.hasPrefix("en") || name.hasPrefix("bridge")),
                  entry.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if isPrivateIPv4(ip), !ip.hasPrefix("127.") { values.append((name, ip)) }
        }
        var seen: Set<String> = []
        return values.sorted {
            if $0.0.hasPrefix("en") != $1.0.hasPrefix("en") { return $0.0.hasPrefix("en") }
            return $0.0 < $1.0
        }.map(\.1).filter { seen.insert($0).inserted }
    }
}
