import Foundation
import Logging
import Dependencies

/// Routes tool execution requests to the appropriate handler (local or remote)
public actor ToolRouter {
    private let logger = Logger(label: "com.monad.core.tools")
    
    @Dependency(\.sessionManager) private var defaultSessionManager
    private let explicitSessionManager: SessionManager?
    private var sessionManager: SessionManager { explicitSessionManager ?? defaultSessionManager }

    public init(sessionManager: SessionManager? = nil) {
        self.explicitSessionManager = sessionManager
    }

    /// Execute a tool in the context of a session
    public func execute(
        tool: ToolReference,
        arguments: [String: AnyCodable],
        sessionId: UUID
    ) async throws -> String {
        logger.info("Routing execution for tool: \(tool.displayName) in session \(sessionId)")

        // 1. Resolve Tool Location
        guard let workspaceId = try await resolveWorkspace(for: tool, in: sessionId) else {
            throw ToolError.toolNotFound(tool.displayName)
        }

        // 2. Get Workspace Details
        guard let workspace = try await sessionManager.getWorkspace(workspaceId) else {
            throw ToolError.workspaceNotFound(workspaceId)
        }

        switch workspace.hostType {
        case .server, .serverSession:
            // 3a. Execute Locally
            return try await executeLocally(tool: tool, arguments: arguments, workspace: workspace, sessionId: sessionId)

        case .client:
            // 3b. Execute Remotely
            return try await executeRemotely(tool: tool, arguments: arguments, workspace: workspace)
        }
    }

    private func resolveWorkspace(for tool: ToolReference, in sessionId: UUID) async throws -> UUID? {
        let workspaces = await sessionManager.getWorkspaces(for: sessionId)
        guard let wsList = workspaces else { return nil }

        var candidates: [UUID] = []
        if let p = wsList.primary { candidates.append(p.id) }
        candidates.append(contentsOf: wsList.attached.map { $0.id })

        return try await sessionManager.findWorkspaceForTool(tool, in: candidates)
    }

    private func executeLocally(
        tool: ToolReference,
        arguments: [String: AnyCodable],
        workspace: WorkspaceReference,
        sessionId: UUID
    ) async throws -> String {
        logger.info("Executing locally: \(tool.displayName)")
        
        guard let toolManager = await sessionManager.getToolManager(for: sessionId) else {
            throw ToolError.toolNotFound(tool.displayName)
        }
        
        guard let realTool = await toolManager.getTool(id: tool.toolId) else {
             throw ToolError.toolNotFound(tool.displayName)
        }
        
        // Convert arguments to [String: Any] for the tool
        var params: [String: Any] = [:]
        for (key, val) in arguments {
            params[key] = val.value
        }
        
        let result = try await realTool.execute(parameters: params)
        if result.success {
            return result.output
        } else {
            throw ToolError.executionFailed(result.error ?? "Unknown error")
        }
    }

    private func executeRemotely(
        tool: ToolReference,
        arguments: [String: AnyCodable],
        workspace: WorkspaceReference
    ) async throws -> String {
        logger.info("Executing remotely on client: \(workspace.ownerId?.uuidString ?? "unknown")")
        
        guard workspace.ownerId != nil else {
            throw ToolError.clientNotConnected
        }

        // In the core framework, we throw this special error to tell the 
        // transport layer (Server/CLI) that client intervention is needed.
        throw ToolError.clientExecutionRequired
    }
}
