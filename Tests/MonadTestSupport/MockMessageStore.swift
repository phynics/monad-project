import MonadShared
import MonadCore
import Foundation

public final class MockMessageStore: MessageStoreProtocol, @unchecked Sendable {
    public var messages: [ConversationMessage] = []

    public init() {}

    public func saveMessage(_ message: ConversationMessage) async throws {
        messages.append(message)
    }

    public func fetchMessages(for timelineId: UUID) async throws -> [ConversationMessage] {
        return messages.filter { $0.timelineId == timelineId }
    }

    public func deleteMessages(for timelineId: UUID) async throws {
        messages.removeAll(where: { $0.timelineId == timelineId })
    }

    public func pruneMessages(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws -> Int {
        return 0
    }
}
