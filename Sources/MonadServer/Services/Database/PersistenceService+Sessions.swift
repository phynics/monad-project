import MonadShared
import MonadCore
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

// Methods moved to MonadServerCore/Extensions/PersistenceService+Server.swift

// Methods moved to MonadServerCore/Extensions/PersistenceService+Server.swift
}
