import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct SessionController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/", use: create)
        group.get("/", use: list)
        group.get("/{id}/history", use: getHistory)

        // Workspace routes
        group.post("/{id}/workspaces", use: attachWorkspace)
        group.delete("/{id}/workspaces/{wsId}", use: detachWorkspace)
        group.get("/{id}/workspaces", use: listWorkspaces)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let session = try await sessionManager.createSession()
        let response = SessionAPIResponse(from: session)
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        let sessions = try await sessionManager.listSessions()
        let response = sessions.map { SessionAPIResponse(from: $0) }
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func getHistory(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let messages = try await sessionManager.getHistory(for: id)
        let data = try SerializationUtils.jsonEncoder.encode(messages)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    
    // MARK: - DTOs
    
    struct SessionAPIResponse: Codable {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let isArchived: Bool
        let tags: [String]
        let workingDirectory: String?
        let primaryWorkspaceId: UUID?
        let attachedWorkspaceIds: [UUID]
        
        init(from session: ConversationSession) {
            self.id = session.id
            self.title = session.title
            self.createdAt = session.createdAt
            self.updatedAt = session.updatedAt
            self.isArchived = session.isArchived
            self.tags = session.tagArray
            self.workingDirectory = session.workingDirectory
            self.primaryWorkspaceId = session.primaryWorkspaceId
            self.attachedWorkspaceIds = session.attachedWorkspaces
        }
    }

    // MARK: - Workspace Endpoints

    @Sendable func attachWorkspace(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        // Decode request body
        let input = try await request.decode(as: AttachWorkspaceRequest.self, context: context)

        try await sessionManager.attachWorkspace(
            input.workspaceId, to: id, isPrimary: input.isPrimary)

        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers)
    }

    @Sendable func detachWorkspace(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        let wsIdString = try context.parameters.require("wsId")

        guard let id = UUID(uuidString: idString), let wsId = UUID(uuidString: wsIdString) else {
            throw HTTPError(.badRequest)
        }

        try await sessionManager.detachWorkspace(wsId, from: id)
        return Response(status: .noContent)
    }

    @Sendable func listWorkspaces(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let workspaces = await sessionManager.getWorkspaces(for: id) else {
            throw HTTPError(.notFound)
        }

        let response = SessionWorkspacesResponse(
            primaryWorkspaceId: workspaces.primary,
            attachedWorkspaceIds: workspaces.attached
        )

        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}
