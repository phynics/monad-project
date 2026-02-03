import Foundation
import GRDB

extension PersistenceService {
    /// Save a compactification node to the database
    public func saveCompactificationNode(_ node: CompactificationNode, sessionId: UUID) throws {
        logger.debug("Saving compactification node \(node.id) for session: \(sessionId)")
        let record = CompactificationNodeRecord(sessionId: sessionId, node: node)
        try dbQueue.write { db in
            try record.save(db)
        }
    }

    /// Fetch all compactification nodes for a session
    public func fetchCompactificationNodes(for sessionId: UUID) throws -> [CompactificationNode] {
        try dbQueue.read { db in
            try CompactificationNodeRecord
                .filter(Column("sessionId") == sessionId)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map { $0.toNode() }
        }
    }

    /// Delete compactification nodes for a session
    public func deleteCompactificationNodes(for sessionId: UUID) throws {
        _ = try dbQueue.write { db in
            try CompactificationNodeRecord
                .filter(Column("sessionId") == sessionId)
                .deleteAll(db)
        }
    }
}
