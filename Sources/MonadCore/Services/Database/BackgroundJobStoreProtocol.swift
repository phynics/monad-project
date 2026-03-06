import MonadShared
/// Protocol for managing background jobs and the subagent task queue.

import Foundation

public protocol BackgroundJobStoreProtocol: Sendable {
    func saveJob(_ job: BackgroundJob) async throws
    func fetchJob(id: UUID) async throws -> BackgroundJob?
    func fetchAllJobs() async throws -> [BackgroundJob]
    func fetchJobs(for timelineId: UUID) async throws -> [BackgroundJob]
    func fetchPendingJobs(limit: Int) async throws -> [BackgroundJob]
    func deleteJob(id: UUID) async throws
    func monitorJobs() async -> AsyncStream<BackgroundJobEvent>
}
