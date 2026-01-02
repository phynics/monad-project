import Foundation
import Observation
import MonadCore

/// Session-specific tool settings
@Observable
@MainActor
public final class SessionToolManager {
    public var enabledTools: Set<String> = []

    /// Available tools in the system
    public let availableTools: [Tool]

    public init(availableTools: [Tool]) {
        self.availableTools = availableTools
        // Enable all tools by default
        self.enabledTools = Set(availableTools.map { $0.id })
    }

    /// Get tools that are currently enabled
    public func getEnabledTools() -> [Tool] {
        availableTools.filter { enabledTools.contains($0.id) }
    }

    /// Toggle tool enabled state
    public func toggleTool(_ toolId: String) {
        if enabledTools.contains(toolId) {
            enabledTools.remove(toolId)
        } else {
            enabledTools.insert(toolId)
        }
    }

    /// Get tool by ID
    public func getTool(id: String) -> Tool? {
        availableTools.first { $0.id == id }
    }
}
