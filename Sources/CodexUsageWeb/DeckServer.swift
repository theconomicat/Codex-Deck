import Foundation
import Network

/// A deliberately small LAN API. It never exposes the Codex debugging port.
@MainActor
public final class DeckServer {
    public private(set) var port = 0
    public private(set) var hosts: [String] = []
    public var isRunning: Bool { listener != nil && port != 0 }
    public var connectedDeviceCount: Int { router.connectedDeviceCount }
    public var pairingExpiresAt: Date? { router.pairingExpiresAt }
    public var onState: (@MainActor () async throws -> Data)? {
        get { router.onState }
        set { router.onState = newValue }
    }
    public var onPreset: (@MainActor (Data) async throws -> Data)? {
        get { router.onPreset }
        set { router.onPreset = newValue }
    }
    public var onChange: (@MainActor () -> Void)? {
        get { router.onChange }
        set { router.onChange = newValue }
    }

    private let router = DeckRouter()
    private let bindHost: String?
    private var listener: NWListener?
    private var starting: CheckedContinuation<Void, Error>?
    private var connections: [UUID: DeckConnection] = [:]

    /// Specify loopback for isolated tests. Production defaults to a private LAN interface.
    public init(bindHost: String? = nil) { self.bindHost = bindHost }

    public static func validateResources() throws { _ = try loadAssets() }

    public func start() async throws {
        guard listener == nil else { throw DeckHTTPError(status: 409, message: "Web Deck is already started.") }
        let available = DeckNetwork.localIPv4Addresses()
        let host = bindHost ?? available.first ?? "127.0.0.1"
        guard host == "127.0.0.1" || available.contains(host) else {
            throw DeckHTTPError(status: 400, message: "Choose a private address on this Mac.")
        }
        router.staticAssets = try Self.loadAssets()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: .any)
        parameters.includePeerToPeer = false
        parameters.allowLocalEndpointReuse = false
        let next = try NWListener(using: parameters)
        hosts = [host]
        listener = next
        next.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        next.stateUpdateHandler = { [weak self, weak next] state in
            Task { @MainActor in
                guard let self, let next, self.listener === next else { return }
                switch state {
                case .ready:
                    guard let value = next.port else {
                        self.failStart(DeckHTTPError(status: 503, message: "Could not determine the Web Deck port."))
                        return
                    }
                    self.port = Int(value.rawValue)
                    self.router.allowedHosts = ["\(host):\(self.port)"]
                    if host == "127.0.0.1" { self.router.allowedHosts.insert("localhost:\(self.port)") }
                    self.router.rotatePairing()
                    let continuation = self.starting
                    self.starting = nil
                    continuation?.resume()
                case .failed(let error):
                    self.failStart(error)
                default:
                    break
                }
            }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                starting = continuation
                next.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    public func stop() {
        let previous = listener
        listener = nil
        previous?.cancel()
        let continuation = starting
        starting = nil
        continuation?.resume(throwing: CancellationError())
        for connection in connections.values { connection.close() }
        connections.removeAll()
        port = 0
        hosts = []
        router.allowedHosts.removeAll()
        router.revokeAll()
    }

    public func rotatePairing() {
        guard isRunning else { return }
        router.rotatePairing()
    }

    public func disconnectDevices() {
        router.revokeAll()
        if isRunning { router.rotatePairing() }
    }

    /// The token is in the fragment so browsers do not send it in HTTP requests/referrers.
    public func pairingURL(host: String) -> URL? {
        guard isRunning, hosts.contains(host), let token = router.pairingToken,
              let expiry = router.pairingExpiresAt, expiry > Date() else { return nil }
        var value = URLComponents()
        value.scheme = "http"
        value.host = host
        value.port = port
        value.path = "/"
        value.fragment = "pair=\(token)"
        return value.url
    }

    private func failStart(_ error: Error) {
        let continuation = starting
        starting = nil
        stop()
        continuation?.resume(throwing: error)
    }

    private func accept(_ connection: NWConnection) {
        guard isRunning, connections.count < 16,
              case .hostPort(let address, _) = connection.endpoint,
              DeckNetwork.isPrivateIPv4(String(describing: address)) else {
            connection.cancel()
            return
        }
        let id = UUID()
        let client = DeckConnection(connection: connection, peer: String(describing: address), router: router) { [weak self] in
            self?.connections.removeValue(forKey: id)
        }
        connections[id] = client
        client.start()
    }

    private static func loadAssets() throws -> [String: (Data, String)] {
        let packaged = Bundle.main.url(forResource: "Codex-Usage_CodexUsageWeb", withExtension: "bundle")
            .flatMap { Bundle(url: $0) }
        let bundle = packaged ?? Bundle.module
        var assets: [String: (Data, String)] = [:]
        for (route, filename, type) in [
            ("/", "index.html", "text/html; charset=utf-8"),
            ("/deck.js", "deck.js", "text/javascript; charset=utf-8"),
            ("/deck.css", "deck.css", "text/css; charset=utf-8")
        ] {
            guard let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Resources") else {
                throw DeckHTTPError(status: 503, message: "The Web Deck resource is missing. Reinstall Codex-Usage.")
            }
            assets[route] = (try Data(contentsOf: url), type)
        }
        return assets
    }
}

@MainActor
private final class DeckConnection {
    let connection: NWConnection
    let peer: String
    let router: DeckRouter
    let onClose: @MainActor () -> Void
    var buffer = Data()
    var timeout: Task<Void, Never>?
    var requestTask: Task<Void, Never>?
    var closed = false
    var responding = false

    init(connection: NWConnection, peer: String, router: DeckRouter, onClose: @escaping @MainActor () -> Void) {
        self.connection = connection
        self.peer = peer
        self.router = router
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed = state { self?.close() }
                if case .cancelled = state { self?.close() }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.close()
        }
        receive()
    }

    func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_769 - buffer.count) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data { self.buffer.append(data) }
                do {
                    if let request = try DeckHTTPRequest.parse(self.buffer) {
                        self.requestTask = Task { [weak self] in
                            guard let self, !Task.isCancelled else { return }
                            let response = await self.router.route(request, peer: self.peer)
                            guard !Task.isCancelled else { return }
                            self.respond(response)
                        }
                    } else if complete || error != nil {
                        self.respond(.error(400, "Incomplete request."))
                    } else {
                        self.receive()
                    }
                } catch let error as DeckHTTPError {
                    self.respond(.error(error.status, error.message))
                } catch {
                    self.respond(.error(400, "Invalid request."))
                }
            }
        }
    }

    func respond(_ response: DeckHTTPResponse) {
        guard !closed, !responding else { return }
        responding = true
        connection.send(content: response.encoded(), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close() }
        })
    }

    func close() {
        guard !closed else { return }
        closed = true
        timeout?.cancel()
        timeout = nil
        requestTask?.cancel()
        requestTask = nil
        connection.cancel()
        onClose()
    }
}
