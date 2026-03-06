import Foundation
import MonadCore
import MonadShared

public extension MonadClient {
    // MARK: - Workspace API

    func createWorkspace(
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

    func listWorkspaces() async throws -> [WorkspaceReference] {
        let request = try buildRequest(path: "/api/workspaces", method: "GET")
        let response: PaginatedResponse<WorkspaceReference> = try await perform(request)
        return response.items
    }

    func getWorkspace(_ id: UUID) async throws -> WorkspaceReference {
        let request = try buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "GET")
        return try await perform(request)
    }

    func updateWorkspace(
        id: UUID,
        rootPath: String? = nil,
        trustLevel: WorkspaceTrustLevel? = nil
    ) async throws -> WorkspaceReference {
        var request = try buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "PATCH")
        request.httpBody = try encoder.encode(
            UpdateWorkspaceRequest(rootPath: rootPath, trustLevel: trustLevel)
        )
        return try await perform(request)
    }

    func deleteWorkspace(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    func addWorkspaceTool(_ tool: ToolReference, workspaceId: UUID) async throws {
        var request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/tools", method: "POST"
        )
        request.httpBody = try encoder.encode(RegisterToolRequest(tool: tool))
        _ = try await performRaw(request)
    }

    /// Atomically replaces all tools for a workspace with the provided set.
    /// Workspace providers should call this on every connect/reconnect to push their current tool list.
    func syncWorkspaceTools(_ tools: [ToolReference], workspaceId: UUID) async throws {
        var request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/tools", method: "PUT"
        )
        request.httpBody = try encoder.encode(SyncToolsRequest(tools: tools))
        _ = try await performRaw(request)
    }

    func listWorkspaceTools(workspaceId: UUID) async throws -> [ToolReference] {
        let request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/tools", method: "GET"
        )
        return try await perform(request)
    }

    func attachWorkspace(_ workspaceId: UUID, to sessionId: UUID, isPrimary: Bool)
        async throws {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces", method: "POST"
        )
        request.httpBody = try encoder.encode(
            AttachWorkspaceRequest(workspaceId: workspaceId, isPrimary: isPrimary)
        )
        _ = try await performRaw(request)
    }

    func detachWorkspace(_ workspaceId: UUID, from sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces/\(workspaceId.uuidString)",
            method: "DELETE"
        )
        _ = try await performRaw(request)
    }

    func listSessionWorkspaces(sessionId: UUID) async throws -> (
        primary: WorkspaceReference?, attached: [WorkspaceReference]
    ) {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces", method: "GET"
        )
        let response: SessionWorkspacesResponse = try await perform(request)
        return (response.primaryWorkspace, response.attachedWorkspaces)
    }

    func restoreWorkspace(sessionId: UUID, workspaceId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces/\(workspaceId.uuidString)/restore",
            method: "POST"
        )
        _ = try await performRaw(request)
    }
}
