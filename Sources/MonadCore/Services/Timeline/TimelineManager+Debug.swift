import MonadShared
import Foundation

extension TimelineManager {
    // MARK: - Debug Snapshots

    /// Store the debug snapshot for the most recent chat exchange in a session
    public func setDebugSnapshot(_ snapshot: DebugSnapshot, for timelineId: UUID) {
        debugSnapshots[timelineId] = snapshot
    }

    /// Retrieve the debug snapshot for the most recent chat exchange
    public func getDebugSnapshot(for timelineId: UUID) -> DebugSnapshot? {
        return debugSnapshots[timelineId]
    }
}
