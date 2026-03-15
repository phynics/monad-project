import Dependencies
import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import MonadShared
import NIOCore

public struct TimelineAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.timelineManager) var timelineManager
    @Dependency(\.timelinePersistence) var timelineStore

    public init() {}

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/", use: create)
        group.get("/", use: list)
        group.get("/{id}", use: get)
        group.patch("/{id}", use: update)
        group.delete("/{id}", use: delete)

        // Messages
        group.get("/{id}/messages", use: getMessages)
        group.get("/{id}/history", use: getMessages) // Legacy alias

        // Workspace routes
        group.post("/{id}/workspaces", use: attachWorkspace)
        group.delete("/{id}/workspaces/{wsId}", use: detachWorkspace)
        group.post("/{id}/workspaces/{wsId}/restore", use: restoreWorkspace)
        group.get("/{id}/workspaces", use: listWorkspaces)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let input = try? await request.decode(as: CreateTimelineRequest.self, context: context)
        let timeline = try await timelineManager.createTimeline(
            title: input?.title ?? "New Conversation"
        )
        let response = TimelineResponse(
            id: timeline.id,
            title: timeline.title,
            createdAt: timeline.createdAt,
            updatedAt: timeline.updatedAt,
            isArchived: timeline.isArchived,
            workingDirectory: timeline.workingDirectory,
            attachedWorkspaceIds: timeline.attachedWorkspaceIds,
            attachedAgentInstanceId: timeline.attachedAgentInstanceId
        )
        return try response.response(status: .created, from: request, context: context)
    }

    @Sendable func list(_ request: Request, context _: Context) async throws -> some ResponseGenerator {
        let pagination = request.getPagination()
        let page = pagination.page
        let perPage = pagination.perPage

        let timelines = try await timelineManager.listTimelines()

        // In-memory pagination
        let total = timelines.count
        let start = (page - 1) * perPage
        let paginatedTimelines: [Timeline]
        if start < total {
            let end = min(start + perPage, total)
            paginatedTimelines = Array(timelines[start ..< end])
        } else {
            paginatedTimelines = []
        }

        let timelineResponses = paginatedTimelines.map { timeline in
            TimelineResponse(
                id: timeline.id,
                title: timeline.title,
                createdAt: timeline.createdAt,
                updatedAt: timeline.updatedAt,
                isArchived: timeline.isArchived,
                workingDirectory: timeline.workingDirectory,
                attachedWorkspaceIds: timeline.attachedWorkspaceIds,
                attachedAgentInstanceId: timeline.attachedAgentInstanceId
            )
        }

        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        return PaginatedResponse(items: timelineResponses, metadata: metadata)
    }

    @Sendable func get(_: Request, context: Context) async throws -> TimelineResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let timeline = await timelineManager.getTimeline(id: id) else {
            // Fallback to DB if not in memory
            if let dbTimeline = try? await timelineStore.fetchTimeline(id: id) {
                return TimelineResponse(
                    id: dbTimeline.id,
                    title: dbTimeline.title,
                    createdAt: dbTimeline.createdAt,
                    updatedAt: dbTimeline.updatedAt,
                    isArchived: dbTimeline.isArchived,
                    workingDirectory: dbTimeline.workingDirectory,
                    attachedWorkspaceIds: dbTimeline.attachedWorkspaceIds,
                    attachedAgentInstanceId: dbTimeline.attachedAgentInstanceId
                )
            }
            throw HTTPError(.notFound)
        }

        return TimelineResponse(
            id: timeline.id,
            title: timeline.title,
            createdAt: timeline.createdAt,
            updatedAt: timeline.updatedAt,
            isArchived: timeline.isArchived,
            workingDirectory: timeline.workingDirectory,
            attachedWorkspaceIds: timeline.attachedWorkspaceIds,
            attachedAgentInstanceId: timeline.attachedAgentInstanceId
        )
    }

    @Sendable func update(_ request: Request, context: Context) async throws -> TimelineResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let input = try await request.decode(as: UpdateTimelineRequest.self, context: context)

        if let title = input.title {
            try await timelineManager.updateTimelineTitle(id: id, title: title)
        }

        return try await get(request, context: context)
    }

    @Sendable func delete(_: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        // Remove from memory
        await timelineManager.deleteTimeline(id: id)

        // Remove from DB
        try await timelineStore.deleteTimeline(id: id)

        return .noContent
    }

    @Sendable func getMessages(_ request: Request, context: Context) async throws -> some ResponseGenerator {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let pagination = request.getPagination(defaultPerPage: 50)
        let page = pagination.page
        let perPage = pagination.perPage

        let messages = try await timelineManager.getHistory(for: id)

        // In-memory pagination
        let total = messages.count
        let start = (page - 1) * perPage
        let paginatedMessages: [Message]
        if start < total {
            let end = min(start + perPage, total)
            paginatedMessages = Array(messages[start ..< end])
        } else {
            paginatedMessages = []
        }

        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        return PaginatedResponse(items: paginatedMessages, metadata: metadata)
    }

    // MARK: - Workspace Endpoints

    @Sendable func attachWorkspace(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let input = try await request.decode(as: AttachWorkspaceRequest.self, context: context)

        try await timelineManager.attachWorkspace(input.workspaceId, to: id)

        return .ok
    }

    @Sendable func detachWorkspace(_: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let wsIdString = try context.parameters.require("wsId")

        guard let id = UUID(uuidString: idString), let wsId = UUID(uuidString: wsIdString) else {
            throw HTTPError(.badRequest)
        }

        try await timelineManager.detachWorkspace(wsId, from: id)
        return .noContent
    }

    @Sendable func listWorkspaces(_: Request, context: Context) async throws -> TimelineWorkspacesResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let workspaces = await timelineManager.getWorkspaces(for: id) else {
            throw HTTPError(.notFound)
        }

        return TimelineWorkspacesResponse(
            primaryWorkspace: workspaces.primary,
            attachedWorkspaces: workspaces.attached
        )
    }

    @Sendable func restoreWorkspace(_: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let wsIdString = try context.parameters.require("wsId")

        guard UUID(uuidString: idString) != nil, let wsId = UUID(uuidString: wsIdString) else {
            throw HTTPError(.badRequest)
        }

        try await timelineManager.restoreWorkspace(wsId)

        return .ok
    }
}
