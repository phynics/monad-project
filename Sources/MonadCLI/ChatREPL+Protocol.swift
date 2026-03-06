import Foundation
import MonadClient

extension ChatREPL {
    // MARK: - ChatREPLController

    func stop() async {
        running = false
    }

    func switchSession(_ newSession: Session) async {
        session = newSession
        selectedWorkspaceId = nil
        LocalConfigManager.shared.updateLastSessionId(newSession.id.uuidString)
        TerminalUI.printInfo("Switched to session \(newSession.id.uuidString.prefix(8))")
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
