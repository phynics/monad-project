import Foundation
import GRDB
import Hummingbird
import Logging
import MonadCore
import HTTPTypes
import NIOCore

/// Controller for managing workspaces
public struct WorkspaceAPIController<Context: RequestContext>: Sendable {
    let persistenceService: any WorkspacePersistenceProtocol & ToolPersistenceProtocol
    let logger: Logger

    public init(persistenceService: any WorkspacePersistenceProtocol & ToolPersistenceProtocol, logger: Logger) {
        self.persistenceService = persistenceService
        self.logger = logger
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post(use: create)
        group.get(use: list)
        group.get(":workspaceId", use: get)
        group.patch(":workspaceId", use: update)
        group.delete(":workspaceId", use: delete)
        group.post(":workspaceId/tools", use: addTool)
        group.get(":workspaceId/tools", use: listTools)
    }

    /// POST /workspaces
    @Sendable func create(request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: CreateWorkspaceRequest.self, context: context)

        // Parse URI
        guard let uri = WorkspaceURI(parsing: input.uri) else {
            throw HTTPError(.badRequest, message: "Invalid workspace URI format")
        }

        let id = UUID()
        let now = Date()

        let workspace = WorkspaceReference(
            id: id,
            uri: uri,
            hostType: input.hostType,
            ownerId: input.ownerId,
            rootPath: input.rootPath,
            trustLevel: input.trustLevel ?? .full,
            createdAt: now
        )

        try await persistenceService.saveWorkspace(workspace)

        return try workspace.response(status: .created, from: request, context: context)
    }

    /// GET /workspaces
    @Sendable func list(request: Request, context: Context) async throws -> some ResponseGenerator {
        let pagination = request.getPagination()
        let page = pagination.page
        let perPage = pagination.perPage

        let workspaces = try await persistenceService.fetchAllWorkspaces()

        // In-memory pagination
        let total = workspaces.count
        let start = (page - 1) * perPage
        let paginatedWorkspaces: [WorkspaceReference]
        if start < total {
            let end = min(start + perPage, total)
            paginatedWorkspaces = Array(workspaces[start..<end])
        } else {
            paginatedWorkspaces = []
        }

        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        return PaginatedResponse(items: paginatedWorkspaces, metadata: metadata)
    }

    public func getWorkspace(id: UUID) async throws -> WorkspaceReference? {
        return try await persistenceService.fetchWorkspace(id: id)
    }

    /// GET /workspaces/:id
    @Sendable func get(request: Request, context: Context) async throws -> WorkspaceReference {
        let id = try context.parameters.require("workspaceId", as: UUID.self)
        let workspace = try await getWorkspace(id: id)

        guard let workspace = workspace else {
            throw HTTPError(.notFound)
        }

        return workspace
    }

    /// PATCH /workspaces/:id
    @Sendable func update(request: Request, context: Context) async throws -> WorkspaceReference {
        let id = try context.parameters.require("workspaceId", as: UUID.self)
        let input = try await request.decode(as: UpdateWorkspaceRequest.self, context: context)

        guard var workspace = try await persistenceService.fetchWorkspace(id: id) else {
            throw HTTPError(.notFound)
        }

        if let rootPath = input.rootPath {
            workspace.rootPath = rootPath
        }
        if let trustLevel = input.trustLevel {
            workspace.trustLevel = trustLevel
        }

        try await persistenceService.saveWorkspace(workspace)

        return workspace
    }

    /// DELETE /workspaces/:id
    @Sendable func delete(request: Request, context: Context) async throws -> HTTPResponse.Status {
        let id = try context.parameters.require("workspaceId", as: UUID.self)
        try await persistenceService.deleteWorkspace(id: id)
        return .noContent
    }

    /// POST /workspaces/:id/tools
    @Sendable func addTool(request: Request, context: Context) async throws -> HTTPResponse.Status {
        let id = try context.parameters.require("workspaceId", as: UUID.self)
        let input = try await request.decode(as: RegisterToolRequest.self, context: context)

        try await persistenceService.addToolToWorkspace(workspaceId: id, tool: input.tool)

        return .created
    }

    /// GET /workspaces/:id/tools
    @Sendable func listTools(request: Request, context: Context) async throws -> [ToolReference] {
        let id = try context.parameters.require("workspaceId", as: UUID.self)

        return try await persistenceService.fetchTools(forWorkspaces: [id])
    }
}
