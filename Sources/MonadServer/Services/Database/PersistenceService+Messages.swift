import MonadShared
import MonadCore
import Foundation
import GRDB

extension PersistenceService {
    public func saveMessage(_ message: ConversationMessage) throws {
        logger.debug("Saving message for session: \(message.timelineId)")
        try dbQueue.write { db in
            try message.save(db)
        }
    }

    public func fetchMessages(for timelineId: UUID) throws -> [ConversationMessage] {
        try dbQueue.read { db in
            try ConversationMessage
                .filter(Column("timelineId") == timelineId)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    public func deleteMessages(for timelineId: UUID) throws {
        _ = try dbQueue.write { db in
            try ConversationMessage
                .filter(Column("timelineId") == timelineId)
                .deleteAll(db)
        }
    }
}
