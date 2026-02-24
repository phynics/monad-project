import Foundation

extension SessionManager {
    // MARK: - Debug Snapshots

    /// Store the debug snapshot for the most recent chat exchange in a session
    public func setDebugSnapshot(_ snapshot: DebugSnapshot, for sessionId: UUID) {
        debugSnapshots[sessionId] = snapshot
    }

    /// Retrieve the debug snapshot for the most recent chat exchange
    public func getDebugSnapshot(for sessionId: UUID) -> DebugSnapshot? {
        return debugSnapshots[sessionId]
    }
}
