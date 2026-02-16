import MonadShared
import Foundation
import Logging

/// Session-specific tool settings
public actor SessionToolManager {
    public private(set) var enabledTools: Set<String> = []

    /// available tools in the system
    public private(set) var availableTools: [any Tool]
    
    /// Context session for dynamic tool injection
    public let contextSession: ToolContextSession?

    /// Registered workspaces providing tools
    private var workspaces: [UUID: any WorkspaceProtocol] = [:]
    
    /// Cached workspace tools
    private var workspaceTools: [String: WorkspaceToolWrapper] = [:]

    public init(availableTools: [any Tool], contextSession: ToolContextSession? = nil) {
        self.availableTools = availableTools
        self.contextSession = contextSession
        // Enable all tools by default
        self.enabledTools = Set(availableTools.map { $0.id })
    }

    /// Update available tools
    public func updateAvailableTools(_ tools: [any Tool]) {
        self.availableTools = tools
        // Keep enabledTools set in sync with available tools (don't remove enabled status if tool still exists)
        let newIds = Set(tools.map { $0.id })
        self.enabledTools = self.enabledTools.intersection(newIds)
        // Auto-enable new tools? Let's say yes for now to avoid breaking changes.
        for id in newIds where !self.enabledTools.contains(id) {
            self.enabledTools.insert(id)
        }
    }

    /// Register a workspace and load its tools
    public func registerWorkspace(_ workspace: any WorkspaceProtocol) async {
        workspaces[workspace.id] = workspace
        await refreshWorkspaceTools()
    }

    /// Unregister a workspace
    public func unregisterWorkspace(_ id: UUID) async {
        workspaces.removeValue(forKey: id)
        await refreshWorkspaceTools()
    }

    /// Refresh tools from all registered workspaces
    private func refreshWorkspaceTools() async {
        var newTools: [String: WorkspaceToolWrapper] = [:]
        
        for workspace in workspaces.values {
            do {
                let refs = try await workspace.listTools()
                for ref in refs {
                    switch ref {
                    case .known:
                         // Known tools are either system tools (already in availableTools) or handled specially.
                         // If we want to expose them as workspace-bound, we'd need to wrap them differently.
                         // For now, ignroe known tools as they likely duplicate system tools.
                         // Or log it.
                         break
                    case .custom(let def):
                         let wrapper = WorkspaceToolWrapper(workspace: workspace, definition: def)
                         newTools[wrapper.id] = wrapper
                    }
                }
            } catch {
                // Log error but continue
                print("Failed to list tools for workspace \(workspace.id): \(error)")
            }
        }
        
        self.workspaceTools = newTools
    }

    /// Get tools that are currently enabled, including context tools if a context is active
    public func getEnabledTools() async -> [any Tool] {
        var tools = availableTools.filter { enabledTools.contains($0.id) }

        // Include context tools if a context is active
        if let session = contextSession, await session.hasActiveContext {
            tools.append(contentsOf: await session.getContextTools())
        }
        
        // Include workspace tools
        tools.append(contentsOf: workspaceTools.values.map { $0 as any Tool })

        return tools
    }
    
    public func getAvailableTools() -> [any Tool] {
        var tools = availableTools
        tools.append(contentsOf: workspaceTools.values.map { $0 as any Tool })
        return tools
    }

    /// Toggle tool enabled state
    public func toggleTool(_ toolId: String) {
        if enabledTools.contains(toolId) {
            enabledTools.remove(toolId)
        } else {
            enabledTools.insert(toolId)
        }
    }
    
    /// Enable a tool explicitly
    public func enableTool(id: String) {
        // Only enable if it is available (checking system tools)
        // Workspace tools are always enabled if present for now?
        if availableTools.contains(where: { $0.id == id }) {
            enabledTools.insert(id)
        }
    }
    
    /// Disable a tool explicitly
    public func disableTool(id: String) {
        enabledTools.remove(id)
    }

    /// Get tool by ID (checks system, context, and workspace tools)
    public func getTool(id: String) async -> (any Tool)? {
        // First check regular system tools
        if let tool = availableTools.first(where: { $0.id == id }) {
            return tool
        }

        // Then check context tools if a context is active
        if let session = contextSession, await session.hasActiveContext {
            if let tool = await session.getContextTools().first(where: { $0.id == id }) {
                return tool
            }
        }
        
        // Then check workspace tools
        if let tool = workspaceTools[id] {
            return tool
        }

        return nil
    }
}