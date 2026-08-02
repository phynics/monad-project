import Foundation
import GRDB
import Hummingbird
import Logging
import PositronicKit
import PKShared
import MonadShared

/// Controller for managing client identities
public struct ClientAPIController<Context: RequestContext>: Sendable {
    private let requestOriginStore: any RequestOriginStoreProtocol
    private let workspaceStore: any WorkspaceStore
    private let toolStore: any ToolPersistenceProtocol

    public init(
        requestOriginStore: any RequestOriginStoreProtocol,
        workspaceStore: any WorkspaceStore,
        toolStore: any ToolPersistenceProtocol
    ) {
        self.requestOriginStore = requestOriginStore
        self.workspaceStore = workspaceStore
        self.toolStore = toolStore
    }

    public init() {
        self.init(
            requestOriginStore: InMemoryRequestOriginStore(),
            workspaceStore: InMemoryWorkspacePersistence(),
            toolStore: InMemoryToolPersistence()
        )
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("register", use: register)
        group.get(":id", use: get)
        group.get(use: list)
        group.delete(":id", use: delete)
    }

    /// POST /clients/register
    @Sendable func register(request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: RequestOriginRegistrationRequest.self, context: context)

        // Generate ID
        let id = UUID()
        let now = Date()

        let requestOrigin = RequestOriginIdentity(
            id: id,
            hostname: input.hostname,
            displayName: input.displayName,
            platform: input.platform,
            registeredAt: now,
            lastSeenAt: now
        )

        // Create default shell workspace
        let workspaceUri = requestOrigin.shellWorkspaceURI
        let defaultWorkspace = WorkspaceReference(
            uri: workspaceUri,
            location: .attached,
            originId: id,
            rootPath: nil, // Unknown until client reports it, or assume home
            trustLevel: .full
        )

        try await requestOriginStore.saveOrigin(requestOrigin)
        try await workspaceStore.saveWorkspace(defaultWorkspace)

        // Save tools
        for toolRef in input.tools {
            try await toolStore.addToolToWorkspace(workspaceId: defaultWorkspace.id, tool: toolRef)
        }

        let response = RequestOriginRegistrationResponse(
            origin: requestOrigin, defaultWorkspace: defaultWorkspace
        )
        return try response.response(status: .created, from: request, context: context)
    }

    /// GET /clients/:id
    @Sendable func get(request _: Request, context: Context) async throws -> RequestOriginIdentity {
        let id = try context.parameters.require("id", as: UUID.self)
        let requestOrigin = try await requestOriginStore.fetchOrigin(id: id)

        guard let requestOrigin = requestOrigin else {
            throw HTTPError(.notFound)
        }

        return requestOrigin
    }

    /// GET /clients
    @Sendable func list(request _: Request, context _: Context) async throws -> [RequestOriginIdentity] {
        return try await requestOriginStore.fetchAllOrigins()
    }

    /// DELETE /clients/:id
    @Sendable func delete(request _: Request, context: Context) async throws -> HTTPResponse.Status {
        let id = try context.parameters.require("id", as: UUID.self)
        let deleted = try await requestOriginStore.deleteOrigin(id: id)

        guard deleted else {
            throw HTTPError(.notFound)
        }

        return .noContent
    }
}

// MARK: - GRDB Conformance for RequestOriginIdentity

// Extended in MonadCore
