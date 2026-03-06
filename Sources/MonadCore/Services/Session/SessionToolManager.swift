import Foundation
import MonadShared
import Logging

/// Session-specific tool settings
public actor SessionToolManager {
    public private(set) var enabledTools: Set<String> = []

    /// available tools in the system
    public private(set) var availableTools: [AnyTool]

    /// Context session for dynamic tool injection
    public let contextSession: ToolContextSession?

    /// Registered workspaces providing tools
    private var workspaces: [UUID: any WorkspaceProtocol] = [:]

    /// Cached workspace tools: toolId -> (wrapper, provenance string)
    private var workspaceTools: [String: (tool: WorkspaceToolWrapper, provenance: String)] = [:]

    /// Cached known-tool overrides from workspaces: toolId -> provenance string
    private var knownToolProvenance: [String: String] = [:]

    public init(availableTools: [AnyTool], contextSession: ToolContextSession? = nil) {
        self.availableTools = availableTools
        self.contextSession = contextSession
        // Enable all tools by default
        self.enabledTools = Set(availableTools.map { $0.id })
    }

    /// Update available tools
    public func updateAvailableTools(_ tools: [AnyTool]) {
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
        var newTools: [String: (tool: WorkspaceToolWrapper, provenance: String)] = [:]
        var newKnownProvenance: [String: String] = [:]

        for workspace in workspaces.values {
            let provenanceTag = "Workspace: \(workspace.reference.uri.description)"
            do {
                let refs = try await workspace.listTools()
                for ref in refs {
                    switch ref {
                    case .known(let toolId):
                        // Tag the system tool with this workspace's provenance
                        if availableTools.contains(where: { $0.id == toolId }) {
                            newKnownProvenance[toolId] = provenanceTag
                        } else {
                            let logger = Logger(label: "com.monad.session-tool-manager")
                            logger.warning("Workspace declared .known tool '\(toolId)' but it is not a registered system tool")
                        }
                    case .custom(let def):
                        let wrapper = WorkspaceToolWrapper(workspace: workspace, definition: def)
                        newTools[wrapper.id] = (tool: wrapper, provenance: provenanceTag)
                    }
                }
            } catch {
                let logger = Logger(label: "com.monad.session-tool-manager")
                logger.error("Failed to list tools for workspace \(workspace.id): \(error)")
            }
        }

        self.workspaceTools = newTools
        self.knownToolProvenance = newKnownProvenance
    }

    /// Get tools that are currently enabled, including context tools if a context is active
    public func getEnabledTools() async -> [AnyTool] {
        var tools = availableTools.filter { enabledTools.contains($0.id) }

        // Apply workspace provenance to .known system tools
        tools = tools.map { tool in
            if let provenance = knownToolProvenance[tool.id] {
                var tagged = tool
                tagged.provenance = provenance
                return tagged
            }
            return tool
        }

        // Include context tools if a context is active
        if let session = contextSession, await session.hasActiveContext {
            tools.append(contentsOf: await session.getContextTools())
        }

        // Include workspace custom tools with provenance
        tools.append(contentsOf: workspaceTools.values.map { entry in
            var tool = AnyTool(entry.tool)
            tool.provenance = entry.provenance
            return tool
        })

        return tools
    }

    public func getAvailableTools() -> [AnyTool] {
        var tools = availableTools

        // Apply provenance to .known system tools
        tools = tools.map { tool in
            if let provenance = knownToolProvenance[tool.id] {
                var tagged = tool
                tagged.provenance = provenance
                return tagged
            }
            return tool
        }

        // Append workspace custom tools with provenance
        tools.append(contentsOf: workspaceTools.values.map { entry in
            var tool = AnyTool(entry.tool)
            tool.provenance = entry.provenance
            return tool
        })
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
    public func getTool(id: String) async -> AnyTool? {
        // First check regular system tools
        if let tool = availableTools.first(where: { $0.id == id }) {
            if let provenance = knownToolProvenance[id] {
                var tagged = tool
                tagged.provenance = provenance
                return tagged
            }
            return tool
        }

        // Then check context tools if a context is active
        if let session = contextSession, await session.hasActiveContext {
            if let tool = await session.getContextTools().first(where: { $0.id == id }) {
                return tool
            }
        }

        // Then check workspace tools
        if let entry = workspaceTools[id] {
            var tool = AnyTool(entry.tool)
            tool.provenance = entry.provenance
            return tool
        }

        return nil
    }
}
