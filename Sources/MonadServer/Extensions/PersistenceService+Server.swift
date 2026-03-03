import Foundation
import GRDB
import Logging
import MonadCore

extension PersistenceService {
    /// Search archived sessions by title, tags, or message content
    public func searchArchivedSessions(query: String) throws -> [Timeline] {
        try dbQueue.read { database in
            let pattern = "%\(query)%"

            // Subquery to find session IDs that have matching messages
            let matchingMessageSessionIds =
                try ConversationMessage
                .filter(Column("content").like(pattern))
                .select(Column("sessionId"))
                .fetchAll(database)
                .map { $0 as UUID }

            return
                try Timeline
                .filter(Column("isArchived") == true)
                .filter(
                    Column("title").like(pattern) || Column("tags").like(pattern)
                        || matchingMessageSessionIds.contains(Column("id"))
                )
                .order(Column("updatedAt").desc)
                .fetchAll(database)
        }
    }

    /// Search for archived sessions that contain any of the provided tags
    public func searchArchivedSessions(matchingAnyTag tags: [String]) throws
        -> [Timeline] {
        guard !tags.isEmpty else { return [] }

        return try dbQueue.read { database in
            var conditions: [SQLExpression] = []
            for tag in tags {
                conditions.append(Column("tags").like("%\(tag)%"))
            }

            let query = conditions.joined(operator: .or)

            let candidates =
                try Timeline
                .filter(Column("isArchived") == true)
                .filter(query)
                .fetchAll(database)

            return candidates.filter {
                let sessionTags = Set($0.tagArray.map { $0.lowercased() })
                return !sessionTags.isDisjoint(with: tags.map { $0.lowercased() })
            }
        }
    }

    public func pruneSessions(
        olderThan timeInterval: TimeInterval, excluding: [UUID] = [], dryRun: Bool
    )
        async throws -> Int {
        try await dbQueue.write { database in
            let cutoffDate = Date().addingTimeInterval(-timeInterval)

            var query = Timeline.filter(Column("updatedAt") < cutoffDate)
                .filter(Column("isArchived") == false)

            if !excluding.isEmpty {
                query = query.filter(!excluding.contains(Column("id")))
            }

            if dryRun {
                return try query.fetchCount(database)
            } else {
                let candidates = try query.fetchAll(database)
                var deletedCount = 0
                for session in candidates {
                    // Double check before deleting
                    if session.isArchived {
                        // Logger not available here, silently skip or use print if critical debug needed
                        continue
                    }

                    do {
                        let didDelete = try Timeline.deleteOne(
                            database, key: ["id": session.id])
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
        -> Int {
        try await dbQueue.write { database in
            let cutoffDate = Date().addingTimeInterval(-timeInterval)
            let query =
                ConversationMessage
                .filter(Column("timestamp") < cutoffDate)
                .filter(
                    sql: "sessionId IN (SELECT id FROM conversationSession WHERE isArchived = 0)")

            if dryRun {
                return try query.fetchCount(database)
            } else {
                return try query.deleteAll(database)
            }
        }
    }

    public func pruneMemories(matching query: String, dryRun: Bool) async throws -> Int {
        try await dbQueue.write { database in
            let pattern = "%\(query)%"
            let request =
                Memory
                .filter(
                    Column("title").like(pattern) || Column("content").like(pattern)
                        || Column("tags").like(pattern)
                )

            if dryRun {
                return try request.fetchCount(database)
            } else {
                return try request.deleteAll(database)
            }
        }
    }

    public func pruneMemories(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws
        -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)

        return try await dbQueue.write { database in
            let request =
                Memory
                .filter(Column("createdAt") < cutoffDate)

            if dryRun {
                return try request.fetchCount(database)
            } else {
                return try request.deleteAll(database)
            }
        }
    }
}
