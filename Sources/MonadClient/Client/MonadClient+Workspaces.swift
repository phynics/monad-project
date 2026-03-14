import Foundation
import MonadShared

public extension MonadWorkspaceClient {
    // MARK: - Workspace API

    func createWorkspace(
        uri: WorkspaceURI,
        hostType: WorkspaceReference.WorkspaceHostType,
        ownerId: UUID?,
        rootPath: String?,
        trustLevel: WorkspaceTrustLevel?
    ) async throws -> WorkspaceReference {
        var request = try await client.buildRequest(path: "/api/workspaces", method: "POST")
        request.httpBody = try await client.encode(
            CreateWorkspaceRequest(
                uri: uri.description,
                hostType: hostType,
                ownerId: ownerId,
                rootPath: rootPath,
                trustLevel: trustLevel
            )
        )
        return try await client.perform(request)
    }

    func listWorkspaces() async throws -> [WorkspaceReference] {
        let request = try await client.buildRequest(path: "/api/workspaces", method: "GET")
        let response: PaginatedResponse<WorkspaceReference> = try await client.perform(request)
        return response.items
    }

    func getWorkspace(_ id: UUID) async throws -> WorkspaceReference {
        let request = try await client.buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "GET")
        return try await client.perform(request)
    }

    func updateWorkspace(
        id: UUID,
        rootPath: String? = nil,
        trustLevel: WorkspaceTrustLevel? = nil
    ) async throws -> WorkspaceReference {
        var request = try await client.buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "PATCH")
        request.httpBody = try await client.encode(
            UpdateWorkspaceRequest(rootPath: rootPath, trustLevel: trustLevel)
        )
        return try await client.perform(request)
    }

    func deleteWorkspace(_ id: UUID) async throws {
        let request = try await client.buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "DELETE")
        _ = try await client.performRaw(request)
    }

    func addWorkspaceTool(_ tool: ToolReference, workspaceId: UUID) async throws {
        var request = try await client.buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/tools", method: "POST"
        )
        request.httpBody = try await client.encode(RegisterToolRequest(tool: tool))
        _ = try await client.performRaw(request)
    }

    /// Atomically replaces all tools for a workspace with the provided set.
    /// Workspace providers should call this on every connect/reconnect to push their current tool list.
    func syncWorkspaceTools(_ tools: [ToolReference], workspaceId: UUID) async throws {
        var request = try await client.buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/tools", method: "PUT"
        )
        request.httpBody = try await client.encode(SyncToolsRequest(tools: tools))
        _ = try await client.performRaw(request)
    }

    func listWorkspaceTools(workspaceId: UUID) async throws -> [ToolReference] {
        let request = try await client.buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/tools", method: "GET"
        )
        return try await client.perform(request)
    }

    func attachWorkspace(_ workspaceId: UUID, to timelineId: UUID) async throws {
        var request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/workspaces", method: "POST"
        )
        request.httpBody = try await client.encode(AttachWorkspaceRequest(workspaceId: workspaceId))
        _ = try await client.performRaw(request)
    }

    func detachWorkspace(_ workspaceId: UUID, from timelineId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/workspaces/\(workspaceId.uuidString)",
            method: "DELETE"
        )
        _ = try await client.performRaw(request)
    }

    func listTimelineWorkspaces(timelineId: UUID) async throws -> (
        primary: WorkspaceReference?, attached: [WorkspaceReference]
    ) {
        let request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/workspaces", method: "GET"
        )
        let response: TimelineWorkspacesResponse = try await client.perform(request)
        return (response.primaryWorkspace, response.attachedWorkspaces)
    }

    func restoreWorkspace(timelineId: UUID, workspaceId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/workspaces/\(workspaceId.uuidString)/restore",
            method: "POST"
        )
        _ = try await client.performRaw(request)
    }
}
