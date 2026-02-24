import Foundation

public final class MockJobStore: JobStoreProtocol, @unchecked Sendable {
    public var jobs: [Job] = []

    public init() {}

    public func saveJob(_ job: Job) async throws {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
    }

    public func fetchJob(id: UUID) async throws -> Job? {
        return jobs.first(where: { $0.id == id })
    }

    public func fetchAllJobs() async throws -> [Job] {
        return jobs
    }

    public func fetchJobs(for sessionId: UUID) async throws -> [Job] {
        return jobs.filter { $0.sessionId == sessionId }
    }

    public func fetchPendingJobs(limit: Int) async throws -> [Job] {
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

    public func monitorJobs() async -> AsyncStream<JobEvent> {
        return AsyncStream { _ in }
    }
}
