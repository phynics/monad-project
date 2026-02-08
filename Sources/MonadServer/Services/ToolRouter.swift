import Foundation
import Logging
import MonadCore

/// Routes tool execution requests to the appropriate handler (local or remote)
public actor ToolRouter {
    private let logger = Logger(label: "com.monad.server.tools")
    // Connection manager needed to send requests to clients
    // However, connection manager might be part of SessionManager or separate.
    // For now, let's assume we can inject a way to send messages to clients.

    // We need a way to look up where a tool resides.
    // ToolRouter needs access to Database to resolve ToolReference -> Workspace -> Host.

    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    /// Execute a tool in the context of a session
    public func execute(
        tool: ToolReference,
        arguments: [String: AnyCodable],
        sessionId: UUID
    ) async throws -> String {
        logger.info("Routing execution for tool: \(tool.displayName) in session \(sessionId)")

        // 1. Resolve Tool Location
        // We need to find which workspace this tool belongs to in the current session context.
        // The session has a primary workspace and attached workspaces.
        // We need to query the database to find which of these workspaces contains the tool.

        // Optimisation: If it's a known server tool (e.g. "memory_search"), it might not be in a workspace DB table if it's "global".
        // But our design says tools are attached to workspaces.
        // Server tools should be in the "Server Workspace".

        // Let's ask SessionManager/DB to resolve the workspace for this tool in this session.
        guard let workspaceId = try await resolveWorkspace(for: tool, in: sessionId) else {
            throw ToolError.toolNotFound(tool.displayName)
        }

        // 2. Get Workspace Details
        // We need to know the HostType of the workspace.
        guard let workspace = try await sessionManager.getWorkspace(workspaceId) else {
            throw ToolError.workspaceNotFound(workspaceId)
        }

        switch workspace.hostType {
        case .server:
            // 3a. Execute Locally
            return try await executeLocally(tool: tool, arguments: arguments, workspace: workspace)

        case .client:
            // 3b. Execute Remotely
            return try await executeRemotely(tool: tool, arguments: arguments, workspace: workspace)
        }
    }

    private func resolveWorkspace(for tool: ToolReference, in sessionId: UUID) async throws -> UUID?
    {
        // Resolve keys


        let workspaces = await sessionManager.getWorkspaces(for: sessionId)
        guard let wsList = workspaces else { return nil }

        var candidates: [UUID] = []
        if let p = wsList.primary { candidates.append(p.id) }
        candidates.append(contentsOf: wsList.attached.map { $0.id })

        // Check database for "WorkspaceTool" via SessionManager

        return try await sessionManager.findWorkspaceForTool(tool, in: candidates)
    }

    private func executeLocally(
        tool: ToolReference,
        arguments: [String: AnyCodable],
        workspace: Workspace
    ) async throws -> String {
        logger.info("Executing locally: \(tool.displayName)")
        // Access registered local tools service?
        // We need a registry of actual Tool implementations on the server.
        // For now, return stub.
        return "Executed \(tool.displayName) locally."
    }

    private func executeRemotely(
        tool: ToolReference,
        arguments: [String: AnyCodable],
        workspace: Workspace
    ) async throws -> String {
        logger.info("Executing remotely on client: \(workspace.ownerId?.uuidString ?? "unknown")")
        // We need to send a message to the client associated with this workspace.
        // The workspace has an ownerId (CreateWorkspaceRequest has ownerId).
        // If ownerId is nil, we can't route? Or implies current connection?

        guard workspace.ownerId != nil else {
            throw ToolError.clientNotConnected
        }

        // Send execution request via SSE/WebSocket/ConnectionManager
        // Instead of executing, we throw a special error telling ChatController to yield the tool call to the client.
        throw ToolError.clientExecutionRequired
    }
}