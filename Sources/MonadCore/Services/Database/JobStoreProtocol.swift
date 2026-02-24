/// Protocol for managing background jobs and the subagent task queue.

import Foundation

public protocol JobStoreProtocol: Sendable {
    func saveJob(_ job: Job) async throws
    func fetchJob(id: UUID) async throws -> Job?
    func fetchAllJobs() async throws -> [Job]
    func fetchJobs(for sessionId: UUID) async throws -> [Job]
    func fetchPendingJobs(limit: Int) async throws -> [Job]
    func deleteJob(id: UUID) async throws
    func monitorJobs() async -> AsyncStream<JobEvent>
}
