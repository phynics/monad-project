import MonadShared
import Foundation
import GRDB

extension PersistenceService {
    public func saveJob(_ job: Job) async throws {
        try await dbQueue.write { db in
            try job.save(db)
        }
        emit(.jobUpdated(job))
    }
    
    public func fetchJob(id: UUID) async throws -> Job? {
        try await dbQueue.read { db in
            try Job.fetchOne(db, key: id)
        }
    }
    
    public func fetchAllJobs() async throws -> [Job] {
        try await dbQueue.read { db in
            try Job.fetchAll(db)
        }
    }

    public func fetchJobs(for sessionId: UUID) async throws -> [Job] {
        try await dbQueue.read { db in
            try Job.filter(Column("sessionId") == sessionId).fetchAll(db)
        }
    }
    
    public func deleteJob(id: UUID) async throws {
        try await dbQueue.write { db in
            _ = try Job.deleteOne(db, key: id)
        }
        emit(.jobDeleted(id))
    }
    
    public func fetchPendingJobs(limit: Int = 10) async throws -> [Job] {
        try await dbQueue.read { db in
            try Job
                .filter(Column("status") == Job.Status.pending.rawValue)
                .filter(Column("nextRunAt") == nil || Column("nextRunAt") <= Date())
                .order(Column("priority").desc, Column("createdAt").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
