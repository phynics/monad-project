@testable import MonadCore
import Foundation

public final class MockMessageStore: MessageStoreProtocol, @unchecked Sendable {
    public var messages: [ConversationMessage] = []

    public init() {}

    public func saveMessage(_ message: ConversationMessage) async throws {
        messages.append(message)
    }

    public func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] {
        return messages.filter { $0.sessionId == sessionId }
    }

    public func deleteMessages(for sessionId: UUID) async throws {
        messages.removeAll(where: { $0.sessionId == sessionId })
    }
}
