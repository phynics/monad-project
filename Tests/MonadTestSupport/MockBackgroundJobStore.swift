import MonadShared
import MonadCore
import Foundation

public final class MockBackgroundJobStore: BackgroundJobStoreProtocol, @unchecked Sendable {
    public var jobs: [BackgroundJob] = []

    public init() {}

    public func saveJob(_ job: BackgroundJob) async throws {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
    }

    public func fetchJob(id: UUID) async throws -> BackgroundJob? {
        return jobs.first(where: { $0.id == id })
    }

    public func fetchAllJobs() async throws -> [BackgroundJob] {
        return jobs
    }

    public func fetchJobs(for timelineId: UUID) async throws -> [BackgroundJob] {
        return jobs.filter { $0.timelineId == timelineId }
    }

    public func fetchPendingJobs(limit: Int) async throws -> [BackgroundJob] {
        return Array(jobs.filter { $0.status == .pending }
            .sorted {
                 if $0.priority != $1.priority { return $0.priority > $1.priority }
                 return $0.createdAt < $1.createdAt
             }
            .prefix(limit))
    }

    public func deleteJob(id: UUID) async throws {
        jobs.removeAll(where: { $0.id == id })
    }

    public func monitorJobs() async -> AsyncStream<BackgroundJobEvent> {
        return AsyncStream { _ in }
    }
}
