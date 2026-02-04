import Foundation
import GRDB

extension PersistenceService {
    public func saveSession(_ session: ConversationSession) throws {
        logger.debug("Saving session: \(session.id)")
        try dbQueue.write { db in
            try session.save(db)
        }
    }

    public func fetchSession(id: UUID) throws -> ConversationSession? {
        try dbQueue.read { db in
            try ConversationSession.fetchOne(db, key: ["id": id])
        }
    }

    public func fetchAllSessions(includeArchived: Bool = false) throws -> [ConversationSession] {
        try dbQueue.read { db in
            if includeArchived {
                return
                    try ConversationSession
                    .order(Column("updatedAt").desc)
                    .fetchAll(db)
            } else {
                return
                    try ConversationSession
                    .filter(Column("isArchived") == false)
                    .order(Column("updatedAt").desc)
                    .fetchAll(db)
            }
        }
    }

    public func deleteSession(id: UUID) throws {
        _ = try dbQueue.write { db in
            try ConversationSession.deleteOne(db, key: ["id": id])
        }
    }

    /// Search archived sessions by title, tags, or message content
    public func searchArchivedSessions(query: String) throws -> [ConversationSession] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"

            // Subquery to find session IDs that have matching messages
            let matchingMessageSessionIds =
                try ConversationMessage
                .filter(Column("content").like(pattern))
                .select(Column("sessionId"))
                .fetchAll(db)
                .map { $0 as UUID }

            return
                try ConversationSession
                .filter(Column("isArchived") == true)
                .filter(
                    Column("title").like(pattern) || Column("tags").like(pattern)
                        || matchingMessageSessionIds.contains(Column("id"))
                )
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    /// Search for archived sessions that contain any of the provided tags
    public func searchArchivedSessions(matchingAnyTag tags: [String]) throws
        -> [ConversationSession]
    {
        guard !tags.isEmpty else { return [] }

        return try dbQueue.read { db in
            var conditions: [SQLExpression] = []
            for tag in tags {
                conditions.append(Column("tags").like("%\(tag)%"))
            }

            let query = conditions.joined(operator: .or)

            let candidates =
                try ConversationSession
                .filter(Column("isArchived") == true)
                .filter(query)
                .fetchAll(db)

            return candidates.filter {
                let sessionTags = Set($0.tagArray.map { $0.lowercased() })
                return !sessionTags.intersection(tags.map { $0.lowercased() }).isEmpty
            }
        }
    }

    public func pruneSessions(olderThan timeInterval: TimeInterval) throws -> Int {
        try dbQueue.write { db in
            let cutoffDate = Date().addingTimeInterval(-timeInterval)
            let count =
                try ConversationSession
                .filter(Column("isArchived") == false)  // Only prune active sessions? Or archived too? Plan says "sessions". Let's assume all or spec configurable.
                // Wait, triggers block deletion of archived sessions.
                // "Archived sessions cannot be deleted" trigger exists.
                // So we can only prune non-archived sessions.
                .filter(Column("updatedAt") < cutoffDate)
                .deleteAll(db)
            return count
        }
    }
}
