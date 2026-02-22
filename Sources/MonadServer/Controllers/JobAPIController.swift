import Foundation
import HTTPTypes
import Hummingbird
import MonadShared
import MonadCore
import NIOCore

public struct JobAPIController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/{id}/jobs", use: create)
        group.get("/{id}/jobs", use: list)
        group.get("/{id}/jobs/{jobId}", use: get)
        group.delete("/{id}/jobs/{jobId}", use: delete)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let sessionId = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let input = try await request.decode(as: MonadShared.AddJobRequest.self, context: context)
        let persistence = await sessionManager.getPersistenceService()
        
        let job = Job(
            sessionId: sessionId,
            parentId: input.parentId,
            title: input.title,
            description: input.description,
            priority: input.priority,
            agentId: input.agentId ?? "default",
            status: .pending
        )
        
        try await persistence.saveJob(job)
        
        return try job.response(status: .created, from: request, context: context)
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> [Job] {
        let idString = try context.parameters.require("id")
        guard let sessionId = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        return try await persistence.fetchJobs(for: sessionId)
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> Job {
        let jobIdString = try context.parameters.require("jobId")
        guard let jobId = UUID(uuidString: jobIdString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        guard let job = try await persistence.fetchJob(id: jobId) else {
            throw HTTPError(.notFound)
        }
        
        return job
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let jobIdString = try context.parameters.require("jobId")
        guard let jobId = UUID(uuidString: jobIdString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        try await persistence.deleteJob(id: jobId)
        
        return .noContent
    }
}
