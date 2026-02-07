import Foundation
import GRDB
import Logging
import MonadCore

extension PersistenceService {
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
                        // Logger not available here, silently skip or use print if critical debug needed
                        continue
                    }

                    do {
                        let didDelete = try ConversationSession.deleteOne(
                            db, key: ["id": session.id])
                        deletedCount += (didDelete ? 1 : 0)
                    } catch {
                        // Ignore individual failures to continue pruning
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
    
    public func pruneMemories(matching query: String, dryRun: Bool) async throws -> Int {
        try await dbQueue.write { db in
            let pattern = "%\(query)%"
            let request =
                Memory
                .filter(
                    Column("title").like(pattern) || Column("content").like(pattern)
                        || Column("tags").like(pattern)
                )

            if dryRun {
                return try request.fetchCount(db)
            } else {
                return try request.deleteAll(db)
            }
        }
    }
    
    public func pruneMemories(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws
        -> Int
    {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)

        return try await dbQueue.write { db in
            let request =
                Memory
                .filter(Column("createdAt") < cutoffDate)
                .filter(!ConversationMessage.select(Column("memoryId")).contains(Column("id")))

            if dryRun {
                return try request.fetchCount(db)
            } else {
                return try request.deleteAll(db)
            }
        }
    }
}
