import AppKit
import CodexUsageCore
import CodexUsageAutomation
import Foundation
import ServiceManagement

if CommandLine.arguments.contains("--enable-launch-at-login") {
    do {
        if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        guard SMAppService.mainApp.status == .enabled else {
            throw NSError(domain: "CodexUsage.Login", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Approve Codex-Usage in System Settings → General → Login Items, then retry."])
        }
        print("Launch at Login enabled")
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
if CommandLine.arguments.contains("--startup-status") {
    let configured = UserDefaults.standard.integer(forKey: "directBridgePort") != 0
    let automatic = UserDefaults.standard.object(forKey: "autoLaunchCodex") as? Bool ?? configured
    print("Launch at Login: \(SMAppService.mainApp.status == .enabled ? "enabled" : "not enabled")")
    print("Open Codex Automatically: \(automatic ? "enabled" : "disabled")")
    print("Direct switching configured: \(configured)")
    exit(0)
}

if CommandLine.arguments.contains("--check-direct-resources") {
    do {
        try DirectModelSwitcher.validateResources()
        print("Direct switching resources OK")
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--print") {
    do {
        let snapshot = try CodexUsageReader().latestSnapshot()
        print(SnapshotFormatter.textSummary(snapshot))
        exit(0)
    } catch {
        fputs("CodexUsage: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
if CommandLine.arguments.contains("--default-presets") {
    FileHandle.standardOutput.write(try PresetConfiguration.defaults.encoded())
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--validate-presets") {
    do {
        guard CommandLine.arguments.indices.contains(index + 1) else {
            throw PresetError.invalid("Pass the path to presets.json.")
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let config = try PresetConfiguration.decode(Data(contentsOf: url))
        for preset in config.presets.sorted(by: { $0.slot < $1.slot }) {
            print("⌘⌃\(preset.slot)  \(preset.title)")
        }
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reader = CodexUsageReader()
    private let iconRenderer = StatusIconRenderer()
    private let presets = PresetStore()
    private let hotKeys = ModelHotKeys()
    private let directSetup = DirectSwitchSetup()
    private var refreshTimer: Timer?
    private var feedbackTask: Task<Void, Never>?
    private var refreshing = false
    private var switching = false
    private var latestSnapshot: CodexUsageSnapshot?
    private var latestError: String?
    private var switchStatus: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        presets.reload()
        render()
        hotKeys.onSelect = { [weak self] slot in self?.selectPreset(slot) }
        hotKeys.onError = { [weak self] message in
            self?.switchStatus = message
            self?.render()
        }
        directSetup.onChange = { [weak self] in self?.render() }
        hotKeys.start()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        if directSetup.port == 0 || CommandLine.arguments.contains("--setup-direct-switching") {
            openDirectSwitching()
        } else {
            Task {
                switchStatus = await directSetup.restoreOnStartup()
                render()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { hotKeys.stop() }

    @objc private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let reader = reader
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try reader.latestSnapshot() }
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshing = false
                switch result {
                case .success(let snapshot):
                    latestSnapshot = snapshot
                    latestError = nil
                case .failure(let error): latestError = error.localizedDescription
                }
                render()
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        if let snapshot = latestSnapshot, latestError == nil {
            button.image = iconRenderer.image(for: snapshot)
            button.toolTip = SnapshotFormatter.textSummary(snapshot)
        } else {
            button.image = iconRenderer.placeholderImage()
            button.toolTip = latestError ?? "Reading Codex usage…"
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let latestError {
            menu.addItem(withTitle: "Usage unavailable — refresh to retry", action: nil, keyEquivalent: "")
            menu.items.last?.toolTip = latestError
        } else if let snapshot = latestSnapshot {
            if snapshot.windows.isEmpty {
                menu.addItem(withTitle: "No quota windows reported", action: nil, keyEquivalent: "")
            }
            for window in snapshot.windows {
                menu.addItem(withTitle: SnapshotFormatter.menuLine(window, showWindowLabel: snapshot.windows.count > 1), action: nil, keyEquivalent: "")
            }
            menu.addItem(withTitle: "Data as of \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))",
                         action: nil, keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Reading Codex usage…", action: nil, keyEquivalent: "")
        }
        add(menu, "Refresh Usage", #selector(refresh))
        menu.addItem(.separator())
        for preset in presets.configuration.presets.sorted(by: { $0.slot < $1.slot }) {
            let title = preset.title.count > 65 ? String(preset.title.prefix(62)) + "…" : preset.title
            let item = NSMenuItem(title: title, action: #selector(selectPresetFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = preset.slot
            item.toolTip = preset.title
            // Display shortcut text without NSMenu also dispatching the Carbon key.
            item.title += "    ⌃⌘\(preset.slot)"
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if let switchStatus {
            let item = NSMenuItem(title: switchStatus, action: nil, keyEquivalent: "")
            item.toolTip = switchStatus
            menu.addItem(item)
        }
        add(menu, "Enable Direct Switching…", #selector(openDirectSwitching))
        let presetMenu = NSMenu(title: "Model Presets")
        presetMenu.autoenablesItems = false
        add(presetMenu, "Edit Presets…", #selector(editPresets))
        add(presetMenu, "Reload Presets", #selector(reloadPresets))
        if let error = presets.error {
            let item = NSMenuItem(title: "Presets error — previous settings kept", action: #selector(showPresetError), keyEquivalent: "")
            item.target = self
            item.toolTip = error
            presetMenu.addItem(item)
        }
        let presetSettings = NSMenuItem(title: "Model Presets", action: nil, keyEquivalent: "")
        presetSettings.submenu = presetMenu
        menu.addItem(presetSettings)
        menu.addItem(.separator())
        let launch = add(menu, "Launch at Login", #selector(toggleLaunchAtLogin))
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let autoLaunch = add(menu, "Open Codex Automatically", #selector(toggleCodexAutoLaunch))
        autoLaunch.state = directSetup.autoLaunchEnabled ? .on : .off
        autoLaunch.isEnabled = directSetup.port != 0
        autoLaunch.toolTip = "Open Codex with direct switching when the companion starts. Running Codex sessions are never restarted automatically."
        menu.addItem(.separator())
        add(menu, "Quit Codex-Usage", #selector(quit))
        return menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func selectPresetFromMenu(_ sender: NSMenuItem) { selectPreset(sender.tag) }

    private func selectPreset(_ slot: Int) {
        guard !switching else { return }
        guard directSetup.port != 0 else { openDirectSwitching(); return }
        guard let foreground = NSWorkspace.shared.frontmostApplication,
              foreground.bundleIdentifier == ModelHotKeys.codexBundleID else {
            showAlert("Open a Codex chat", "Open the chat you want to change, then press Command–Control–1 through 5.")
            return
        }
        guard foreground.processIdentifier == directSetup.processIdentifier else {
            openDirectSwitching()
            return
        }
        presets.reload() // Saving valid JSON takes effect on the next shortcut.
        render()
        guard let preset = presets.configuration.presets.first(where: { $0.slot == slot }) else { return }
        switching = true
        Task {
            defer { switching = false }
            do {
                _ = try await DirectModelSwitcher(port: directSetup.port).apply(preset)
                switchStatus = "Applied: \(preset.title)"
                showFeedback(preset.title)
            } catch {
                switchStatus = "Model switch needs attention"
                showAlert("Preset could not be confirmed", error.localizedDescription)
            }
            render()
        }
    }

    private func showFeedback(_ text: String) {
        feedbackTask?.cancel()
        statusItem.button?.title = " " + text
        feedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.statusItem.button?.title = ""
        }
    }

    @objc private func editPresets() {
        presets.reload()
        if FileManager.default.fileExists(atPath: presets.url.path) {
            NSWorkspace.shared.open(presets.url)
        } else { showPresetError() }
        render()
    }

    @objc private func reloadPresets() {
        presets.reload()
        render()
        if presets.error != nil { showPresetError() }
        else { showFeedback("Presets reloaded") }
    }

    @objc private func showPresetError() {
        showAlert("Check presets.json", presets.error ?? "Could not open the presets file.")
    }

    @objc private func openDirectSwitching() {
        Task {
            do {
                if try await AppInstallation.installForDirectSwitching() { return }
                directSetup.show()
            } catch {
                showAlert("Could not set up direct switching", error.localizedDescription)
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            render()
        } catch {
            showAlert("Could not update Launch at Login", "Move Codex-Usage.app to /Applications, then try again. \(error.localizedDescription)")
        }
    }

    @objc private func toggleCodexAutoLaunch() {
        directSetup.autoLaunchEnabled.toggle()
        render()
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
