import AppKit
import Darwin

@MainActor
final class DirectSwitchSetup {
    private let defaults = UserDefaults.standard
    private var window: NSWindow?
    private var label: NSTextField?
    private var button: NSButton?
    var onChange: (() -> Void)?

    var port: Int { defaults.integer(forKey: "directBridgePort") }
    var processIdentifier: pid_t { pid_t(defaults.integer(forKey: "directBridgePID")) }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 240),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Codex-Usage · Direct Switching"
            window.isReleasedWhenClosed = false
            let label = NSTextField(wrappingLabelWithString: "Codex를 한 번 재시작하면 모델과 추론 강도를 바로 변경할 수 있습니다.\n\n현재 실행 중인 작업이 끝난 뒤 아래 버튼을 누르세요. 연결은 이 Mac에서만 사용합니다.")
            label.frame = NSRect(x: 24, y: 82, width: 422, height: 132)
            label.font = .systemFont(ofSize: 14)
            window.contentView?.addSubview(label)
            let button = NSButton(title: "Codex 재시작 · 직접 전환 연결", target: self, action: #selector(enable))
            button.frame = NSRect(x: 24, y: 24, width: 422, height: 36)
            button.bezelStyle = .rounded
            window.contentView?.addSubview(button)
            self.label = label
            self.button = button
            self.window = window
            window.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func enable() {
        button?.isEnabled = false
        label?.stringValue = "Codex를 재시작하고 있습니다…"
        Task {
            defer { button?.isEnabled = true }
            do {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ModelHotKeys.codexBundleID) else {
                    throw NSError(domain: "CodexUsage.Setup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Codex 앱을 찾을 수 없습니다."])
                }
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: ModelHotKeys.codexBundleID) {
                    guard app.terminate() else {
                        throw NSError(domain: "CodexUsage.Setup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Codex를 종료한 뒤 다시 눌러주세요."])
                    }
                    for _ in 0..<100 {
                        if app.isTerminated { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard app.isTerminated else {
                        throw NSError(domain: "CodexUsage.Setup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Codex 종료 확인을 완료한 뒤 다시 눌러주세요."])
                    }
                }
                let port = try Self.availablePort()
                let config = NSWorkspace.OpenConfiguration()
                config.arguments = ["--remote-debugging-address=127.0.0.1", "--remote-debugging-port=\(port)"]
                config.createsNewApplicationInstance = true
                let launched = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                defaults.set(port, forKey: "directBridgePort")
                defaults.set(Int(launched.processIdentifier), forKey: "directBridgePID")
                onChange?()
                label?.stringValue = "Codex를 직접 전환 모드로 실행했습니다.\n\n채팅을 열고 ⌘⌃1~5를 눌러주세요. 연결과 모델 변경의 성공 여부는 단축키 실행 시 확인합니다.\n\nCodex를 Dock에서 다시 실행하면 이 연결 설정을 다시 실행해야 할 수 있습니다."
            } catch {
                label?.stringValue = error.localizedDescription
            }
        }
    }

    private static func availablePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EADDRNOTAVAIL) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw POSIXError(.EADDRNOTAVAIL) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
        }
        guard status == 0 else { throw POSIXError(.EADDRNOTAVAIL) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
