import Foundation
import MonadClient

extension ChatREPL {
    // MARK: - ChatREPLController

    func stop() async {
        running = false
    }

    func switchTimeline(_ newTimeline: Timeline) async {
        timeline = newTimeline
        selectedWorkspaceId = nil
        LocalConfigManager.shared.updateLastSessionId(newTimeline.id.uuidString)
        TerminalUI.printInfo("Switched to timeline \(newTimeline.id.uuidString.prefix(8))")
        await showContext()
        await checkAndRestoreWorkspaces()
    }

    func setSelectedWorkspace(_ id: UUID?) async {
        selectedWorkspaceId = id
    }

    func getSelectedWorkspace() -> UUID? {
        selectedWorkspaceId
    }

    func getLastDebugSnapshot() -> DebugSnapshot? {
        lastDebugSnapshot
    }

    func refreshContext() async {
        await showContext()
    }
}
