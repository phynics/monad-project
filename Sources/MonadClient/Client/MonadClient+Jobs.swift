import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Job API

    /// Add a new job
    public func addJob(sessionId: UUID, title: String, description: String? = nil, priority: Int = 0) async throws -> Job {
        var request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs", method: "POST")
        request.httpBody = try encoder.encode(AddJobRequest(title: title, description: description, priority: priority))
        return try await perform(request)
    }

    /// List jobs for a session
    public func listJobs(sessionId: UUID) async throws -> [Job] {
        let request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs", method: "GET")
        return try await perform(request)
    }

    /// Get a specific job
    public func getJob(sessionId: UUID, jobId: UUID) async throws -> Job {
        let request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs/\(jobId.uuidString)", method: "GET")
        return try await perform(request)
    }

    /// Delete a job
    public func deleteJob(sessionId: UUID, jobId: UUID) async throws {
        let request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs/\(jobId.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }
}
