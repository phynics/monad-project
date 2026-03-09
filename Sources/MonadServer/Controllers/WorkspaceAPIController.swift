import Dependencies
import Foundation
import GRDB
import HTTPTypes
import Hummingbird
import Logging
import MonadCore
import MonadShared
import NIOCore

/// Controller for managing workspaces
public struct WorkspaceAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.workspacePersistence) var workspaceStore
    @Dependency(\.toolPersistence) var toolStore

    public init() {}

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post(use: create)
        group.get(use: list)
        group.get(":workspaceId", use: get)
        group.patch(":workspaceId", use: update)
        group.delete(":workspaceId", use: delete)
        group.post(":workspaceId/tools", use: addTool)
        group.put(":workspaceId/tools", use: syncTools)
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

        try await workspaceStore.saveWorkspace(workspace)

        // Persist any tools declared at creation time
        for tool in input.tools {
            try await toolStore.addToolToWorkspace(workspaceId: id, tool: tool)
        }

        return try workspace.response(status: .created, from: request, context: context)
    }

    /// GET /workspaces
    @Sendable func list(request: Request, context _: Context) async throws -> some ResponseGenerator {
        let pagination = request.getPagination()
        let page = pagination.page
        let perPage = pagination.perPage

        let workspaces = try await workspaceStore.fetchAllWorkspaces()

        // In-memory pagination
        let total = workspaces.count
        let start = (page - 1) * perPage
        let paginatedWorkspaces: [WorkspaceReference]
        if start < total {
            let end = min(start + perPage, total)
            paginatedWorkspaces = Array(workspaces[start ..< end])
        } else {
            paginatedWorkspaces = []
        }

        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        return PaginatedResponse(items: paginatedWorkspaces, metadata: metadata)
    }

    public func getWorkspace(id: UUID) async throws -> WorkspaceReference? {
        return try await workspaceStore.fetchWorkspace(id: id)
    }

    /// GET /workspaces/:id
    @Sendable func get(request _: Request, context: Context) async throws -> WorkspaceReference {
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

        guard var workspace = try await workspaceStore.fetchWorkspace(id: id) else {
            throw HTTPError(.notFound)
        }

        if let rootPath = input.rootPath {
            workspace.rootPath = rootPath
        }
        if let trustLevel = input.trustLevel {
            workspace.trustLevel = trustLevel
        }

        try await workspaceStore.saveWorkspace(workspace)

        return workspace
    }

    /// DELETE /workspaces/:id
    @Sendable func delete(request _: Request, context: Context) async throws -> HTTPResponse.Status {
        let id = try context.parameters.require("workspaceId", as: UUID.self)
        try await workspaceStore.deleteWorkspace(id: id)
        return .noContent
    }

    /// POST /workspaces/:id/tools
    @Sendable func addTool(request: Request, context: Context) async throws -> HTTPResponse.Status {
        let id = try context.parameters.require("workspaceId", as: UUID.self)
        let input = try await request.decode(as: RegisterToolRequest.self, context: context)

        try await toolStore.addToolToWorkspace(workspaceId: id, tool: input.tool)

        return .created
    }

    /// PUT /workspaces/:id/tools — atomically replaces all tools for a workspace.
    /// Workspace providers call this on connect to push their full tool set.
    @Sendable func syncTools(request: Request, context: Context) async throws -> HTTPResponse.Status {
        let id = try context.parameters.require("workspaceId", as: UUID.self)
        let input = try await request.decode(as: SyncToolsRequest.self, context: context)

        try await toolStore.syncTools(workspaceId: id, tools: input.tools)

        return .ok
    }

    /// GET /workspaces/:id/tools
    @Sendable func listTools(request _: Request, context: Context) async throws -> [ToolReference] {
        let id = try context.parameters.require("workspaceId", as: UUID.self)

        return try await toolStore.fetchTools(forWorkspaces: [id])
    }
}
