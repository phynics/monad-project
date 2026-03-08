import MonadShared
import Foundation
import Hummingbird
import MonadCore
import NIOCore
import Dependencies

public struct BackgroundJobAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.timelineManager) var timelineManager
    @Dependency(\.backgroundJobStore) var backgroundJobStore

    public init() {}

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/{id}/jobs", use: create)
        group.get("/{id}/jobs", use: list)
        group.get("/{id}/jobs/{jobId}", use: get)
        group.delete("/{id}/jobs/{jobId}", use: delete)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let timelineId = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let input = try await request.decode(as: AddBackgroundJobRequest.self, context: context)

        let job = BackgroundJob(
            timelineId: timelineId,
            parentId: input.parentId,
            title: input.title,
            description: input.description,
            priority: input.priority,
            agentId: input.agentId ?? "default",
            status: .pending
        )
        try await backgroundJobStore.saveJob(job)

        return try job.response(status: .created, from: request, context: context)
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> [BackgroundJob] {
        let idString = try context.parameters.require("id")
        guard let timelineId = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        return try await backgroundJobStore.fetchJobs(for: timelineId)
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> BackgroundJob {
        let jobIdString = try context.parameters.require("jobId")
        guard let jobId = UUID(uuidString: jobIdString) else { throw HTTPError(.badRequest) }
        guard let job = try await backgroundJobStore.fetchJob(id: jobId) else {
            throw HTTPError(.notFound)
        }

        return job
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let jobIdString = try context.parameters.require("jobId")
        guard let jobId = UUID(uuidString: jobIdString) else { throw HTTPError(.badRequest) }
        try await backgroundJobStore.deleteJob(id: jobId)

        return .noContent
    }
}
