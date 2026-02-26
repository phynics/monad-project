import Foundation

/// Model for database backup/export
public struct DatabaseBackup: Codable, Sendable {
    public let sessions: [Timeline]
    public let messages: [ConversationMessage]
    public let memories: [Memory]

    public init(
        sessions: [Timeline],
        messages: [ConversationMessage],
        memories: [Memory]
    ) {
        self.sessions = sessions
        self.messages = messages
        self.memories = memories
    }
}
