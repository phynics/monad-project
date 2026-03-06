import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - BackgroundJob API

    /// Add a new job
    func addJob(timelineId: UUID, title: String, description: String? = nil, priority: Int = 0) async throws -> BackgroundJob {
        var request = try await client.buildRequest(path: "/api/sessions/\(timelineId.uuidString)/jobs", method: "POST")
        request.httpBody = try await client.encode(AddBackgroundJobRequest(title: title, description: description, priority: priority))
        return try await client.perform(request)
    }

    /// List jobs for a session
    func listJobs(timelineId: UUID) async throws -> [BackgroundJob] {
        let request = try await client.buildRequest(path: "/api/sessions/\(timelineId.uuidString)/jobs", method: "GET")
        return try await client.perform(request)
    }

    /// Get a specific job
    func getJob(timelineId: UUID, jobId: UUID) async throws -> BackgroundJob {
        let request = try await client.buildRequest(path: "/api/sessions/\(timelineId.uuidString)/jobs/\(jobId.uuidString)", method: "GET")
        return try await client.perform(request)
    }

    /// Delete a job
    func deleteJob(timelineId: UUID, jobId: UUID) async throws {
        let request = try await client.buildRequest(path: "/api/sessions/\(timelineId.uuidString)/jobs/\(jobId.uuidString)", method: "DELETE")
        _ = try await client.performRaw(request)
    }
}
