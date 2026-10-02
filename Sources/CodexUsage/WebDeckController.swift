import AppKit
import CoreImage
import CodexUsageWeb

/// Pairing is explicitly started by the Mac user and lasts only this app session.
@MainActor
final class WebDeckController {
    let server = DeckServer()
    private var window: NSWindow?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let address = NSTextField(wrappingLabelWithString: "")
    private let instructions = NSTextField(wrappingLabelWithString: "")
    private let qr = NSImageView()
    private let toggle = NSButton()
    private let copy = NSButton()
    private let renew = NSButton()
    private let revoke = NSButton()
    private var starting = false
    private var expiryTimer: Timer?
    var onChange: (() -> Void)?

    init() {
        server.onChange = { [weak self] in self?.update(); self?.onChange?() }
    }

    func show() {
        if window == nil { buildWindow() }
        update()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func stop() {
        expiryTimer?.invalidate()
        server.stop()
    }

    private func buildWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 550),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Codex-Usage · Web Deck"
        panel.isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "Your phone. Your control deck.")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 478, width: 492, height: 32)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.frame = NSRect(x: 24, y: 440, width: 492, height: 32)
        instructions.font = .systemFont(ofSize: 13)
        instructions.frame = NSRect(x: 24, y: 364, width: 492, height: 66)
        qr.frame = NSRect(x: 160, y: 142, width: 220, height: 220)
        qr.imageScaling = .scaleProportionallyUpOrDown
        address.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        address.alignment = .center
        address.isSelectable = true
        address.frame = NSRect(x: 24, y: 112, width: 492, height: 24)
        for (button, title, action, frame) in [
            (toggle, "Start Web Deck", #selector(toggleServer), NSRect(x: 24, y: 64, width: 158, height: 32)),
            (copy, "Copy Pairing Link", #selector(copyLink), NSRect(x: 191, y: 64, width: 158, height: 32)),
            (renew, "New Pairing Link", #selector(newLink), NSRect(x: 358, y: 64, width: 158, height: 32)),
            (revoke, "Disconnect All Devices", #selector(disconnectDevices), NSRect(x: 156, y: 22, width: 228, height: 30))
        ] {
            button.title = title
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.frame = frame
            panel.contentView?.addSubview(button)
        }
        for view in [heading, status, instructions, qr, address] { panel.contentView?.addSubview(view) }
        panel.center()
        window = panel
    }

    private func update() {
        let running = server.isRunning
        let expired = (server.pairingExpiresAt ?? .distantPast) <= Date()
        expiryTimer?.invalidate()
        expiryTimer = nil
        if running, let deadline = server.pairingExpiresAt, !expired {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.update() }
            }
            expiryTimer?.tolerance = 1
        }
        status.stringValue = running ? "Running · \(server.connectedDeviceCount) paired device(s)" : "Stopped · accessible only after you start it"
        instructions.stringValue = running
            ? (expired ? "Pairing link expired or used. Choose New Pairing Link for another phone. Paired devices remain connected."
                       : "On your phone, join the same trusted Wi-Fi and scan this QR code. This one-use link expires in 5 minutes. Keep it private.")
            : "Start Web Deck, then pair your phone to switch models in your active Codex chat. Use a trusted private network: the local connection uses HTTP."
        toggle.title = running ? "Stop Web Deck" : "Start Web Deck"
        toggle.isEnabled = !starting
        copy.isEnabled = running && !expired
        renew.isEnabled = running
        revoke.isEnabled = running && server.connectedDeviceCount > 0
        if running, let host = server.hosts.first {
            address.stringValue = "http://\(host):\(server.port)"
            if host == "127.0.0.1" {
                instructions.stringValue = "No private network address is available. Join Wi-Fi, then stop and start Web Deck to connect your phone."
            }
            qr.image = expired ? nil : server.pairingURL(host: host).flatMap(Self.qrImage)
        } else {
            address.stringValue = ""
            qr.image = nil
        }
    }

    @objc private func toggleServer() {
        if server.isRunning { stop(); update(); return }
        guard !starting else { return }
        starting = true
        update()
        Task {
            defer { starting = false; update(); onChange?() }
            do {
                try await server.start()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not start Web Deck"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc private func copyLink() {
        guard let host = server.hosts.first, let url = server.pairingURL(host: host) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func newLink() { server.rotatePairing(); update() }
    @objc private func disconnectDevices() { server.disconnectDevices(); update() }

    private static func qrImage(_ url: URL) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        // An opaque quiet zone keeps the QR readable on dark macOS appearances.
        let padding: CGFloat = 32
        let size = NSSize(width: output.extent.width + padding * 2, height: output.extent.height + padding * 2)
        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: image, size: output.extent.size).draw(at: NSPoint(x: padding, y: padding), from: .zero,
                                                          operation: .sourceOver, fraction: 1)
        result.unlockFocus()
        return result
    }
}
