/// Protocol for managing chat history and message persistence.

import Foundation

public protocol MessageStoreProtocol: Sendable {
    func saveMessage(_ message: ConversationMessage) async throws
    func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage]
    func deleteMessages(for sessionId: UUID) async throws
}
