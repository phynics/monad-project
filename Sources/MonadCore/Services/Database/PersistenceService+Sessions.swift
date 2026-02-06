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

    public func pruneSessions(
        olderThan timeInterval: TimeInterval, excluding: [UUID] = [], dryRun: Bool
    )
        async throws -> Int
    {
        try await dbQueue.write { db in
            let cutoffDate = Date().addingTimeInterval(-timeInterval)

            var query = ConversationSession.filter(Column("updatedAt") < cutoffDate)
                .filter(Column("isArchived") == false)

            if !excluding.isEmpty {
                query = query.filter(!excluding.contains(Column("id")))
            }

            if dryRun {
                return try query.fetchCount(db)
            } else {
                let candidates = try query.fetchAll(db)
                var deletedCount = 0
                for session in candidates {
                    // Double check before deleting
                    if session.isArchived {
                        logger.warning(
                            "Skipping prune of archived session found in candidates: \(session.id)")
                        continue
                    }

                    do {
                        let didDelete = try ConversationSession.deleteOne(
                            db, key: ["id": session.id])
                        deletedCount += (didDelete ? 1 : 0)
                        logger.debug("Pruned session: \(session.id)")
                    } catch {
                        logger.error("Failed to prune session \(session.id): \(error)")
                        // Check if we should abort or continue?
                        // For now continue to try pruning others
                    }
                }
                return deletedCount
            }
        }
    }

    public func pruneMessages(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws
        -> Int
    {
        try await dbQueue.write { db in
            let cutoffDate = Date().addingTimeInterval(-timeInterval)
            let query =
                ConversationMessage
                .filter(Column("timestamp") < cutoffDate)
                .filter(
                    sql: "sessionId IN (SELECT id FROM conversationSession WHERE isArchived = 0)")

            if dryRun {
                return try query.fetchCount(db)
            } else {
                return try query.deleteAll(db)
            }
        }
    }
}
