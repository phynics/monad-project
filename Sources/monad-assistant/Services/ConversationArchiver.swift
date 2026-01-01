import Foundation

/// Manages conversation archiving to database
@MainActor
class ConversationArchiver {
    private let persistenceManager: PersistenceManager

    init(persistenceManager: PersistenceManager) {
        self.persistenceManager = persistenceManager
    }

    /// Archive current conversation to database
    func archive(messages: [Message]) async throws {
        guard !messages.isEmpty else { return }

        // Create session if needed
        if persistenceManager.currentSession == nil {
            let title = generateTitle(from: messages)
            try await persistenceManager.createNewSession(title: title)
        }

        // Save all messages
        for message in messages {
            try await persistenceManager.addMessage(
                role: ConversationMessage.MessageRole(rawValue: message.role.rawValue) ?? .user,
                content: message.content
            )
        }

        // Archive the session
        try await persistenceManager.archiveCurrentSession()
    }

    /// Generate conversation title from messages
    private func generateTitle(from messages: [Message]) -> String {
        if let firstMessage = messages.first(where: { $0.role == .user }) {
            let words = firstMessage.content.split(separator: " ").prefix(6)
            return words.joined(separator: " ") + (words.count < 6 ? "" : "...")
        }
        return "Conversation at \(Date().formatted(date: .abbreviated, time: .shortened))"
    }
}
