import Foundation
import GRDB

extension PersistenceService {
    public func saveJob(_ job: Job) async throws {
        try await dbQueue.write { db in
            try job.save(db)
        }
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
    
    public func deleteJob(id: UUID) async throws {
        try await dbQueue.write { db in
            _ = try Job.deleteOne(db, key: id)
        }
    }
}
