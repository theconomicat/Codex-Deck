import Testing
import CodexUsageCore

@Test func codexStartupRequiresSetupAndRespectsOptOut() {
    #expect(CodexStartupAction.resolve(hasSavedConnection: false, autoLaunchEnabled: true,
        runningProcessIDs: [], connectedProcessID: 0) == .disabled)
    #expect(CodexStartupAction.resolve(hasSavedConnection: true, autoLaunchEnabled: false,
        runningProcessIDs: [], connectedProcessID: 42) == .disabled)
}

@Test func codexStartupLaunchesOnlyWhenCodexIsClosed() {
    #expect(CodexStartupAction.resolve(hasSavedConnection: true, autoLaunchEnabled: true,
        runningProcessIDs: [], connectedProcessID: 42) == .launch)
    #expect(CodexStartupAction.resolve(hasSavedConnection: true, autoLaunchEnabled: true,
        runningProcessIDs: [42], connectedProcessID: 42) == .keepRunning)
    #expect(CodexStartupAction.resolve(hasSavedConnection: true, autoLaunchEnabled: true,
        runningProcessIDs: [84], connectedProcessID: 42) == .needsManualConnection)
    #expect(CodexStartupAction.resolve(hasSavedConnection: true, autoLaunchEnabled: true,
        runningProcessIDs: [84, 96], connectedProcessID: 42) == .needsManualConnection)
}
