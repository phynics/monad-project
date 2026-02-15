import Foundation
import HTTPTypes
import Hummingbird
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
        
        let input = try await request.decode(as: AddJobRequest.self, context: context)
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
        
        let data = try SerializationUtils.jsonEncoder.encode(job)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let sessionId = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        let jobs = try await persistence.fetchJobs(for: sessionId)
        
        let data = try SerializationUtils.jsonEncoder.encode(jobs)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> Response {
        let jobIdString = try context.parameters.require("jobId")
        guard let jobId = UUID(uuidString: jobIdString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        guard let job = try await persistence.fetchJob(id: jobId) else {
            throw HTTPError(.notFound)
        }
        
        let data = try SerializationUtils.jsonEncoder.encode(job)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> Response {
        let jobIdString = try context.parameters.require("jobId")
        guard let jobId = UUID(uuidString: jobIdString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        try await persistence.deleteJob(id: jobId)
        
        return Response(status: .noContent)
    }
}
