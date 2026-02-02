import Foundation
import Logging

/// Session-specific tool settings
public actor SessionToolManager {
    public private(set) var enabledTools: Set<String> = []

    /// available tools in the system
    public private(set) var availableTools: [any Tool]

    /// Context session for dynamic tool injection
    public let contextSession: ToolContextSession?

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

    /// Get tools that are currently enabled, including context tools if a context is active
    public func getEnabledTools() async -> [any Tool] {
        var tools = availableTools.filter { enabledTools.contains($0.id) }

        // Include context tools if a context is active
        if let session = contextSession, await session.hasActiveContext {
            tools.append(contentsOf: await session.getContextTools())
        }

        return tools
    }
    
    public func getAvailableTools() -> [any Tool] {
        return availableTools
    }

    /// Toggle tool enabled state
    public func toggleTool(_ toolId: String) {
        if enabledTools.contains(toolId) {
            enabledTools.remove(toolId)
        } else {
            enabledTools.insert(toolId)
        }
    }

    /// Get tool by ID (checks both regular tools and context tools)
    public func getTool(id: String) async -> (any Tool)? {
        // First check regular tools
        if let tool = availableTools.first(where: { $0.id == id }) {
            return tool
        }

        // Then check context tools if a context is active
        if let session = contextSession, await session.hasActiveContext {
            return await session.getContextTools().first { $0.id == id }
        }

        return nil
    }
}