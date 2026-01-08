import Foundation

/// Model for database backup/export
public struct DatabaseBackup: Codable, Sendable {
    public let sessions: [ConversationSession]
    public let messages: [ConversationMessage]
    public let memories: [Memory]
    public let notes: [Note]
    
    public init(
        sessions: [ConversationSession],
        messages: [ConversationMessage],
        memories: [Memory],
        notes: [Note]
    ) {
        self.sessions = sessions
        self.messages = messages
        self.memories = memories
        self.notes = notes
    }
}
