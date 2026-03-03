import MonadCore
import Foundation
import GRDB

extension PersistenceService {
    public func saveSession(_ session: Timeline) throws {
        logger.debug("Saving session: \(session.id)")
        try dbQueue.write { db in
            try session.save(db)
        }
    }

    public func fetchSession(id: UUID) throws -> Timeline? {
        try dbQueue.read { db in
            try Timeline.fetchOne(db, key: ["id": id])
        }
    }

    public func fetchAllSessions(includeArchived: Bool = false) throws -> [Timeline] {
        try dbQueue.read { db in
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

    public func deleteSession(id: UUID) throws {
        _ = try dbQueue.write { db in
            try Timeline.deleteOne(db, key: ["id": id])
        }
    }

// Methods moved to MonadServerCore/Extensions/PersistenceService+Server.swift

// Methods moved to MonadServerCore/Extensions/PersistenceService+Server.swift
}
