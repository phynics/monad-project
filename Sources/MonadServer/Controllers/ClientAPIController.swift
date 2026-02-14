import Foundation
import GRDB
import Hummingbird
import Logging
import MonadCore

/// Controller for managing client identities
public struct ClientAPIController<Context: RequestContext>: Sendable {
    let dbWriter: DatabaseWriter
    let logger: Logger

    public init(dbWriter: DatabaseWriter, logger: Logger) {
        self.dbWriter = dbWriter
        self.logger = logger
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("register", use: register)
        group.get(":id", use: get)
        group.get(use: list)
        group.delete(":id", use: delete)
    }

    /// POST /clients/register
    @Sendable func register(request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: ClientRegistrationRequest.self, context: context)

        // Generate ID
        let id = UUID()
        let now = Date()

        let client = ClientIdentity(
            id: id,
            hostname: input.hostname,
            displayName: input.displayName,
            platform: input.platform,
            registeredAt: now,
            lastSeenAt: now
        )

        // Create default shell workspace
        let workspaceUri = client.shellWorkspaceURI
        let defaultWorkspace = WorkspaceReference(
            uri: workspaceUri,
            hostType: .client,
            ownerId: id,
            rootPath: nil,  // Unknown until client reports it, or assume home
            trustLevel: .full
        )

        try await dbWriter.write { db in
            try client.insert(db)
            try defaultWorkspace.insert(db)

            // Save tools
            for toolRef in input.tools {
                let tool = try WorkspaceTool(
                    workspaceId: defaultWorkspace.id, toolReference: toolRef)
                try tool.insert(db)
            }
        }

        let response = ClientRegistrationResponse(
            client: client, defaultWorkspace: defaultWorkspace)
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    /// GET /clients/:id
    @Sendable func get(request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id", as: UUID.self)
        let client = try await dbWriter.read { db in
            try ClientIdentity.fetchOne(db, key: id)
        }

        guard let client = client else {
            throw HTTPError(.notFound)
        }

        let data = try SerializationUtils.jsonEncoder.encode(client)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    /// GET /clients
    @Sendable func list(request: Request, context: Context) async throws -> Response {
        let clients = try await dbWriter.read { db in
            try ClientIdentity.fetchAll(db)
        }

        let data = try SerializationUtils.jsonEncoder.encode(clients)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    /// DELETE /clients/:id
    @Sendable func delete(request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id", as: UUID.self)
        let deleted = try await dbWriter.write { db in
            try ClientIdentity.deleteOne(db, key: id)
        }

        guard deleted else {
            throw HTTPError(.notFound)
        }

        return Response(status: .noContent)
    }
}

// MARK: - GRDB Conformance for ClientIdentity
// Extended in MonadCore
