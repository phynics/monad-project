import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - Job API

    /// Add a new job
    func addJob(sessionId: UUID, title: String, description: String? = nil, priority: Int = 0) async throws -> Job {
        var request = try await client.buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs", method: "POST")
        request.httpBody = try await client.encode(AddJobRequest(title: title, description: description, priority: priority))
        return try await client.perform(request)
    }

    /// List jobs for a session
    func listJobs(sessionId: UUID) async throws -> [Job] {
        let request = try await client.buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs", method: "GET")
        return try await client.perform(request)
    }

    /// Get a specific job
    func getJob(sessionId: UUID, jobId: UUID) async throws -> Job {
        let request = try await client.buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs/\(jobId.uuidString)", method: "GET")
        return try await client.perform(request)
    }

    /// Delete a job
    func deleteJob(sessionId: UUID, jobId: UUID) async throws {
        let request = try await client.buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs/\(jobId.uuidString)", method: "DELETE")
        _ = try await client.performRaw(request)
    }
}
