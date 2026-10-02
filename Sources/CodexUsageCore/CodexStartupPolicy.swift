public enum CodexStartupAction: Equatable, Sendable {
    case disabled, keepRunning, launch, needsManualConnection

    public static func resolve(hasSavedConnection: Bool, autoLaunchEnabled: Bool,
                               runningProcessIDs: [Int32], connectedProcessID: Int32) -> Self {
        guard hasSavedConnection, autoLaunchEnabled else { return .disabled }
        if runningProcessIDs.isEmpty { return .launch }
        if runningProcessIDs.contains(connectedProcessID) { return .keepRunning }
        // A normally launched Codex may have unfinished work. Only explicit
        // setup may restart it; background startup must never do so.
        return .needsManualConnection
    }
}
