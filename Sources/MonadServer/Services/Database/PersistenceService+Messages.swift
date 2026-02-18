import MonadShared
import MonadCore
import Foundation
import GRDB

extension PersistenceService {
    public func saveMessage(_ message: ConversationMessage) throws {
        logger.debug("Saving message for session: \(message.sessionId)")
        try dbQueue.write { db in
            try message.save(db)
        }
    }

    public func fetchMessages(for sessionId: UUID) throws -> [ConversationMessage] {
        try dbQueue.read { db in
            try ConversationMessage
                .filter(Column("sessionId") == sessionId)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }
    
    public func deleteMessages(for sessionId: UUID) throws {
        _ = try dbQueue.write { db in
            try ConversationMessage
                .filter(Column("sessionId") == sessionId)
                .deleteAll(db)
        }
    }
}
