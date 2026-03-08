import GRDB
import MonadCore
import MonadShared
import Foundation
import Logging

public actor MessageRepository: MessageStoreProtocol {
    private let dbQueue: DatabaseQueue
    private let logger = Logger.module(named: "MessageRepository")

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveMessage(_ message: ConversationMessage) async throws {
        logger.debug("Saving message for session: \(message.timelineId)")
        try await dbQueue.write { db in
            try message.save(db)
        }
    }

    public func fetchMessages(for timelineId: UUID) async throws -> [ConversationMessage] {
        try await dbQueue.read { db in
            try ConversationMessage
                .filter(Column("timelineId") == timelineId)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    public func deleteMessages(for timelineId: UUID) async throws {
        _ = try await dbQueue.write { db in
            try ConversationMessage
                .filter(Column("timelineId") == timelineId)
                .deleteAll(db)
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
                    sql: "timelineId IN (SELECT id FROM timeline WHERE isArchived = 0)")

            if dryRun {
                return try query.fetchCount(database)
            } else {
                return try query.deleteAll(database)
            }
        }
    }
}
