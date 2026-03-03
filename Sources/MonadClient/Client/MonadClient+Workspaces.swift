import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Workspace API

    public func createWorkspace(
        uri: WorkspaceURI,
        hostType: WorkspaceReference.WorkspaceHostType,
        ownerId: UUID?,
        rootPath: String?,
        trustLevel: WorkspaceTrustLevel?
    ) async throws -> WorkspaceReference {
        var request = try buildRequest(path: "/api/workspaces", method: "POST")
        request.httpBody = try encoder.encode(
            CreateWorkspaceRequest(
                uri: uri.description,
                hostType: hostType,
                ownerId: ownerId,
                rootPath: rootPath,
                trustLevel: trustLevel
            )
        )
        return try await perform(request)
    }

    public func listWorkspaces() async throws -> [WorkspaceReference] {
        let request = try buildRequest(path: "/api/workspaces", method: "GET")
        let response: PaginatedResponse<WorkspaceReference> = try await perform(request)
        return response.items
    }

    public func getWorkspace(_ id: UUID) async throws -> WorkspaceReference {
        let request = try buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "GET")
        return try await perform(request)
    }

    public func deleteWorkspace(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    public func attachWorkspace(_ workspaceId: UUID, to sessionId: UUID, isPrimary: Bool)
        async throws {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces", method: "POST")
        request.httpBody = try encoder.encode(
            AttachWorkspaceRequest(workspaceId: workspaceId, isPrimary: isPrimary)
        )
        _ = try await performRaw(request)
    }

    public func detachWorkspace(_ workspaceId: UUID, from sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces/\(workspaceId.uuidString)",
            method: "DELETE"
        )
        _ = try await performRaw(request)
    }

    public func listSessionWorkspaces(sessionId: UUID) async throws -> (
        primary: WorkspaceReference?, attached: [WorkspaceReference]
    ) {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces", method: "GET")
        let response: SessionWorkspacesResponse = try await perform(request)
        return (response.primaryWorkspace, response.attachedWorkspaces)
    }

    public func restoreWorkspace(sessionId: UUID, workspaceId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces/\(workspaceId.uuidString)/restore",
            method: "POST"
        )
        _ = try await performRaw(request)
    }
}
