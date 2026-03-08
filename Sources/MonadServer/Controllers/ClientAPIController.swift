import Foundation
import GRDB
import Hummingbird
import Logging
import MonadShared
import Dependencies

/// Controller for managing client identities
public struct ClientAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.clientStore) var clientStore
    @Dependency(\.workspacePersistence) var workspaceStore
    @Dependency(\.toolPersistence) var toolStore

    public init() {}

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
            rootPath: nil, // Unknown until client reports it, or assume home
            trustLevel: .full
        )

        try await clientStore.saveClient(client)
        try await workspaceStore.saveWorkspace(defaultWorkspace)

        // Save tools
        for toolRef in input.tools {
            try await toolStore.addToolToWorkspace(workspaceId: defaultWorkspace.id, tool: toolRef)
        }

        let response = ClientRegistrationResponse(
            client: client, defaultWorkspace: defaultWorkspace
        )
        return try response.response(status: .created, from: request, context: context)
    }

    /// GET /clients/:id
    @Sendable func get(request _: Request, context: Context) async throws -> ClientIdentity {
        let id = try context.parameters.require("id", as: UUID.self)
        let client = try await clientStore.fetchClient(id: id)

        guard let client = client else {
            throw HTTPError(.notFound)
        }

        return client
    }

    /// GET /clients
    @Sendable func list(request _: Request, context _: Context) async throws -> [ClientIdentity] {
        return try await clientStore.fetchAllClients()
    }

    /// DELETE /clients/:id
    @Sendable func delete(request _: Request, context: Context) async throws -> HTTPResponse.Status {
        let id = try context.parameters.require("id", as: UUID.self)
        let deleted = try await clientStore.deleteClient(id: id)

        guard deleted else {
            throw HTTPError(.notFound)
        }

        return .noContent
    }
}

// MARK: - GRDB Conformance for ClientIdentity

// Extended in MonadCore
