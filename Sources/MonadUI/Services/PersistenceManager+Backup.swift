import Foundation
import MonadCore

extension PersistenceManager {
    public func exportDatabase() async throws -> Data {
        logger.info("Exporting database")
        
        let sessions = try await persistence.fetchAllSessions(includeArchived: true)
        var messages: [ConversationMessage] = []
        for session in sessions {
            let sessionMessages = try await persistence.fetchMessages(for: session.id)
            messages.append(contentsOf: sessionMessages)
        }
        
        let memories = try await persistence.fetchAllMemories()
        let notes = try await persistence.fetchAllNotes()
        
        let backup = DatabaseBackup(
            sessions: sessions,
            messages: messages,
            memories: memories,
            notes: notes
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try encoder.encode(backup)
    }
    
    public func importDatabase(from data: Data) async throws {
        logger.info("Importing database")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(DatabaseBackup.self, from: data)
        
        try await resetDatabase()
        
        for session in backup.sessions {
            try await persistence.saveSession(session)
        }
        for message in backup.messages {
            try await persistence.saveMessage(message)
        }
        for memory in backup.memories {
            _ = try await persistence.saveMemory(memory, policy: .always)
        }
        for note in backup.notes {
            try await persistence.saveNote(note)
        }
        
        await loadActiveSessions()
        await loadArchivedSessions()
    }
}
