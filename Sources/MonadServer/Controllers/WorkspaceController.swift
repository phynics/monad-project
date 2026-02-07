import Foundation
import GRDB
import Hummingbird
import Logging
import MonadCore

/// Controller for managing workspaces
public struct WorkspaceController<Context: RequestContext>: Sendable {
    let dbWriter: DatabaseWriter
    let logger: Logger

    public init(dbWriter: DatabaseWriter, logger: Logger) {
        self.dbWriter = dbWriter
        self.logger = logger
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post(use: create)
        group.get(use: list)
        group.get(":id", use: get)
        group.delete(":id", use: delete)
        group.post(":id/tools", use: addTool)
        group.get(":id/tools", use: listTools)
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

        let workspace = Workspace(
            id: id,
            uri: uri,
            hostType: input.hostType,
            ownerId: input.ownerId,
            rootPath: input.rootPath,
            trustLevel: input.trustLevel ?? .full,
            createdAt: now
        )

        try await dbWriter.write { db in
            try workspace.insert(db)
        }

        let data = try SerializationUtils.jsonEncoder.encode(workspace)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    /// GET /workspaces
    @Sendable func list(request: Request, context: Context) async throws -> Response {
        let workspaces = try await dbWriter.read { db in
            try Workspace.fetchAll(db)
        }
        let data = try SerializationUtils.jsonEncoder.encode(workspaces)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    public func getWorkspace(id: UUID) async throws -> Workspace? {
        return try await dbWriter.read { db in
            try Workspace.fetchOne(db, key: id)
        }
    }

    /// GET /workspaces/:id
    @Sendable func get(request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id", as: UUID.self)
        let workspace = try await getWorkspace(id: id)

        guard let workspace = workspace else {
            throw HTTPError(.notFound)
        }

        let data = try SerializationUtils.jsonEncoder.encode(workspace)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    /// DELETE /workspaces/:id
    @Sendable func delete(request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id", as: UUID.self)
        try await dbWriter.write { db in
            _ = try Workspace.deleteOne(db, key: id)
        }
        return Response(status: .noContent)
    }

    /// POST /workspaces/:id/tools
    @Sendable func addTool(request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id", as: UUID.self)
        let input = try await request.decode(as: RegisterToolRequest.self, context: context)

        try await dbWriter.write { db in
            // Verify workspace exists
            guard try Workspace.exists(db, key: id) else {
                throw HTTPError(.notFound)
            }

            // Create and insert tool
            let tool = try WorkspaceTool(workspaceId: id, toolReference: input.tool)
            try tool.insert(db)
        }

        return Response(status: .created)
    }

    /// GET /workspaces/:id/tools
    @Sendable func listTools(request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id", as: UUID.self)

        let tools = try await dbWriter.read { db -> [ToolReference] in
            guard try Workspace.exists(db, key: id) else {
                throw HTTPError(.notFound)
            }

            let tools =
                try WorkspaceTool
                .filter(Column("workspaceId") == id)
                .fetchAll(db)

            return try tools.map { try $0.toToolReference() }
        }

        let data = try SerializationUtils.jsonEncoder.encode(tools)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}
