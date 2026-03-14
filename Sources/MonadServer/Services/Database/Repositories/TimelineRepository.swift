import Foundation
import GRDB
import Logging
import MonadCore
import MonadShared

public actor TimelineRepository: TimelinePersistenceProtocol {
    private let dbQueue: DatabaseQueue
    private let logger = Logger.module(named: "TimelineRepository")

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveTimeline(_ session: Timeline) async throws {
        logger.debug("Saving session: \(session.id)")
        try await dbQueue.write { db in
            try session.save(db)
        }
    }

    public func fetchTimeline(id: UUID) async throws -> Timeline? {
        try await dbQueue.read { db in
            try Timeline.fetchOne(db, key: ["id": id])
        }
    }

    public func fetchAllTimelines(includeArchived: Bool = false) async throws -> [Timeline] {
        try await dbQueue.read { db in
            if includeArchived {
                return
                    try Timeline
                        .order(Column("updatedAt").desc)
                        .fetchAll(db)
            } else {
                return
                    try Timeline
                        .filter(Column("isArchived") == false)
                        .order(Column("updatedAt").desc)
                        .fetchAll(db)
            }
        }
    }

    public func deleteTimeline(id: UUID) async throws {
        _ = try await dbQueue.write { db in
            try Timeline.deleteOne(db, key: ["id": id])
        }
    }

    /// Search archived timelines by title, tags, or message content
    public func searchArchivedTimelines(query: String) throws -> [Timeline] {
        try dbQueue.read { database in
            let pattern = "%\(query)%"

            // Subquery to find timeline IDs that have matching messages
            let matchingMessageSessionIds =
                try ConversationMessage
                    .filter(Column("content").like(pattern))
                    .select(Column("timelineId"))
                    .fetchAll(database)
                    .map { $0 as UUID }

            return
                try Timeline
                    .filter(Column("isArchived") == true)
                    .filter(
                        Column("title").like(pattern)
                            || matchingMessageSessionIds.contains(Column("id"))
                    )
                    .order(Column("updatedAt").desc)
                    .fetchAll(database)
        }
    }

    public func pruneTimelines(
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
                for timeline in candidates {
                    // Double check before deleting
                    if timeline.isArchived {
                        // Logger not available here, silently skip or use print if critical debug needed
                        continue
                    }

                    do {
                        let didDelete = try Timeline.deleteOne(
                            database, key: ["id": timeline.id]
                        )
                        deletedCount += (didDelete ? 1 : 0)
                    } catch {
                        // Ignore individual failures to continue pruning
                    }
                }
                return deletedCount
            }
        }
    }
}
