import GRDB
import MonadCore
import MonadShared
import Foundation

public actor BackgroundJobRepository: BackgroundJobStoreProtocol {
    private let dbQueue: DatabaseQueue

    private let jobStream: AsyncStream<BackgroundJobEvent>
    private let jobContinuation: AsyncStream<BackgroundJobEvent>.Continuation

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        let (stream, continuation) = AsyncStream.makeStream(of: BackgroundJobEvent.self)
        self.jobStream = stream
        self.jobContinuation = continuation
    }

    public func monitorJobs() async -> AsyncStream<BackgroundJobEvent> {
        return jobStream
    }

    private func emit(_ event: BackgroundJobEvent) {
        jobContinuation.yield(event)
    }

    public func saveJob(_ job: BackgroundJob) async throws {
        try await dbQueue.write { db in
            try job.save(db)
        }
        emit(.jobUpdated(job))
    }

    public func fetchJob(id: UUID) async throws -> BackgroundJob? {
        try await dbQueue.read { db in
            try BackgroundJob.fetchOne(db, key: id)
        }
    }

    public func fetchAllJobs() async throws -> [BackgroundJob] {
        try await dbQueue.read { db in
            try BackgroundJob.fetchAll(db)
        }
    }

    public func fetchJobs(for timelineId: UUID) async throws -> [BackgroundJob] {
        try await dbQueue.read { db in
            try BackgroundJob.filter(Column("timelineId") == timelineId).fetchAll(db)
        }
    }

    public func deleteJob(id: UUID) async throws {
        try await dbQueue.write { db in
            _ = try BackgroundJob.deleteOne(db, key: id)
        }
        emit(.jobDeleted(id))
    }

    public func fetchPendingJobs(limit: Int = 10) async throws -> [BackgroundJob] {
        try await dbQueue.read { db in
            try BackgroundJob
                .filter(Column("status") == BackgroundJob.Status.pending.rawValue)
                .filter(Column("nextRunAt") == nil || Column("nextRunAt") <= Date())
                .order(Column("priority").desc, Column("createdAt").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
