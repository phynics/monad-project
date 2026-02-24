import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct SessionAPIController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

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
        let input = try? await request.decode(as: CreateSessionRequest.self, context: context)
        let session = try await sessionManager.createSession(
            title: input?.title ?? "New Conversation"
        )
        let response = SessionResponse(
            id: session.id,
            title: session.title,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            isArchived: session.isArchived,
            tags: session.tagArray,
            workingDirectory: session.workingDirectory,
            primaryWorkspaceId: session.primaryWorkspaceId,
            attachedWorkspaceIds: session.attachedWorkspaces
        )
        return try response.response(status: .created, from: request, context: context)
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> some ResponseGenerator {
        let pagination = request.getPagination()
        let page = pagination.page
        let perPage = pagination.perPage

        let sessions = try await sessionManager.listSessions()

        // In-memory pagination
        let total = sessions.count
        let start = (page - 1) * perPage
        let paginatedSessions: [ConversationSession]
        if start < total {
            let end = min(start + perPage, total)
            paginatedSessions = Array(sessions[start..<end])
        } else {
            paginatedSessions = []
        }

        let sessionResponses = paginatedSessions.map { session in
            SessionResponse(
                id: session.id,
                title: session.title,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                isArchived: session.isArchived,
                tags: session.tagArray,
                workingDirectory: session.workingDirectory,
                primaryWorkspaceId: session.primaryWorkspaceId,
                attachedWorkspaceIds: session.attachedWorkspaces
            )
        }

        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        return PaginatedResponse(items: sessionResponses, metadata: metadata)
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> SessionResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let session = await sessionManager.getSession(id: id) else {
             // Fallback to DB if not in memory
             let persistence = await sessionManager.getPersistenceService()
             if let dbSession = try? await persistence.fetchSession(id: id) {
                 return SessionResponse(
                     id: dbSession.id,
                     title: dbSession.title,
                     createdAt: dbSession.createdAt,
                     updatedAt: dbSession.updatedAt,
                     isArchived: dbSession.isArchived,
                     tags: dbSession.tagArray,
                     workingDirectory: dbSession.workingDirectory,
                     primaryWorkspaceId: dbSession.primaryWorkspaceId,
                     attachedWorkspaceIds: dbSession.attachedWorkspaces
                 )
             }
             throw HTTPError(.notFound)
        }

        return SessionResponse(
            id: session.id,
            title: session.title,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            isArchived: session.isArchived,
            tags: session.tagArray,
            workingDirectory: session.workingDirectory,
            primaryWorkspaceId: session.primaryWorkspaceId,
            attachedWorkspaceIds: session.attachedWorkspaces
        )
    }

    @Sendable func update(_ request: Request, context: Context) async throws -> SessionResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let input = try await request.decode(as: UpdateSessionRequest.self, context: context)

        if let title = input.title {
            try await sessionManager.updateSessionTitle(id: id, title: title)
        }

        return try await get(request, context: context)
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        // Remove from memory
        await sessionManager.deleteSession(id: id)

        // Remove from DB
        let persistence = await sessionManager.getPersistenceService()
        try await persistence.deleteSession(id: id)

        return .noContent
    }

    @Sendable func getMessages(_ request: Request, context: Context) async throws -> some ResponseGenerator {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let pagination = request.getPagination(defaultPerPage: 50)
        let page = pagination.page
        let perPage = pagination.perPage

        let messages = try await sessionManager.getHistory(for: id)

        // In-memory pagination
        let total = messages.count
        let start = (page - 1) * perPage
        let paginatedMessages: [Message]
        if start < total {
            let end = min(start + perPage, total)
            paginatedMessages = Array(messages[start..<end])
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

        // Decode request body
        let input = try await request.decode(as: AttachWorkspaceRequest.self, context: context)

        try await sessionManager.attachWorkspace(
            input.workspaceId, to: id, isPrimary: input.isPrimary)

        return .ok
    }

    @Sendable func detachWorkspace(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let wsIdString = try context.parameters.require("wsId")

        guard let id = UUID(uuidString: idString), let wsId = UUID(uuidString: wsIdString) else {
            throw HTTPError(.badRequest)
        }

        try await sessionManager.detachWorkspace(wsId, from: id)
        return .noContent
    }

    @Sendable func listWorkspaces(_ request: Request, context: Context) async throws -> SessionWorkspacesResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let workspaces = await sessionManager.getWorkspaces(for: id) else {
            throw HTTPError(.notFound)
        }

        return SessionWorkspacesResponse(
            primaryWorkspace: workspaces.primary,
            attachedWorkspaces: workspaces.attached
        )
    }

    @Sendable func restoreWorkspace(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let wsIdString = try context.parameters.require("wsId")

        guard let _ = UUID(uuidString: idString), let wsId = UUID(uuidString: wsIdString) else {
            throw HTTPError(.badRequest)
        }

        try await sessionManager.restoreWorkspace(wsId)

        return .ok
    }
}
