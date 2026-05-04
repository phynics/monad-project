import Foundation
import MonadClient
import PKShared
import MonadShared

extension ChatREPL {
    // MARK: - ChatREPLController

    func stop() async {
        running = false
    }

    func switchTimeline(_ newTimeline: Timeline) async {
        timeline = newTimeline
        selectedWorkspaceId = nil
        currentAgent = nil
        LocalConfigManager.shared.updateLastSessionId(newTimeline.id.uuidString)
        TerminalUI.printInfo("Switched to timeline \(newTimeline.id.uuidString.prefix(8))")
        await showContext()
        await checkAndRestoreWorkspaces()
    }

    func setAgent(_ agent: AgentInstance?) async {
        currentAgent = agent
    }

    func getCurrentAgent() -> AgentInstance? {
        currentAgent
    }

    func setSelectedWorkspace(_ id: UUID?) async {
        selectedWorkspaceId = id
    }

    func getSelectedWorkspace() -> UUID? {
        selectedWorkspaceId
    }

    func getLastTurnSnapshot() -> TurnSnapshot? {
        lastTurnSnapshot
    }

    func refreshContext() async {
        await showContext()
    }
}
