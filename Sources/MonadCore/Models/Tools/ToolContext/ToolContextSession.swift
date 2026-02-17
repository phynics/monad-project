import MonadShared
import Foundation
import Logging

// MARK: - ContextGatewayTool Protocol

/// A tool that activates a ToolContext when executed.
///
/// Gateway tools are regular tools that, when executed, activate a specific
/// ToolContext and make its context-specific tools available.
public protocol ContextGatewayTool: Tool {
    associatedtype Context: ToolContext

    /// The context instance to activate
    var context: Context { get }

    /// Reference to the context session for activation
    var contextSession: ToolContextSession { get }
}

// MARK: - ToolContextSession

/// Manages the lifecycle of active tool contexts.
///
/// Only one context can be active at a time. When a new context is activated,
/// any existing non-persistent context is first deactivated.
public actor ToolContextSession {
    private let logger = Logger.tools

    /// Currently active context (only one at a time)
    public private(set) var activeContext: (any ToolContext)?

    /// IDs of tools belonging to the active context
    private var contextToolIds: Set<String> = []

    /// Pinned contexts that persist across tool calls and inject state into prompts
    private var pinnedContexts: [String: any ToolContext] = [:]

    public init() {}

    /// Activate a new context (deactivates any existing non-persistent context)
    public func activate(_ context: any ToolContext) async {
        // Deactivate existing context first (only if it's not persistent)
        if let existing = activeContext, !existing.isPersistent {
            logger.info("Deactivating context: \(type(of: existing).contextId)")
            await existing.deactivate()
        }

        activeContext = context
        let tools = await context.contextTools
        contextToolIds = Set(tools.map { $0.id })

        // If context is pinned, add to pinned contexts
        if context.isPinned {
            pinnedContexts[type(of: context).contextId] = context
        }

        logger.info("Activated context: \(type(of: context).contextId)")
        await context.activate()
    }

    /// Deactivate current context (only if not persistent)
    public func deactivate() async {
        guard let context = activeContext else { return }

        // Persistent contexts don't get deactivated by this method
        if context.isPersistent {
            logger.info("Context \(type(of: context).contextId) is persistent, not deactivating")
            return
        }

        logger.info("Deactivating context: \(type(of: context).contextId)")
        await context.deactivate()

        activeContext = nil
        contextToolIds = []
    }

    /// Force deactivate context (even if persistent)
    public func forceDeactivate() async {
        guard let context = activeContext else { return }

        logger.info("Force deactivating context: \(type(of: context).contextId)")
        await context.deactivate()

        // Also remove from pinned if it was pinned
        pinnedContexts.removeValue(forKey: type(of: context).contextId)

        activeContext = nil
        contextToolIds = []
    }

    /// Unpin a context
    public func unpin(_ contextId: String) async {
        if let context = pinnedContexts.removeValue(forKey: contextId) {
            logger.info("Unpinned context: \(contextId)")
            await context.deactivate()
        }
    }

    /// Check if a tool belongs to the active context
    public func isContextTool(_ toolId: String) -> Bool {
        contextToolIds.contains(toolId)
    }

    /// Check if a tool is a gateway tool for the active context
    public func isActiveContextGateway(_ toolId: String) -> Bool {
        guard let context = activeContext else { return false }
        return type(of: context).contextId == toolId
    }

    /// Get context tools if a context is active
    public func getContextTools() async -> [AnyTool] {
        await activeContext?.contextTools ?? []
    }

    /// Check if any context is active
    public var hasActiveContext: Bool {
        activeContext != nil
    }

    /// Get the ID of the active context, if any
    public var activeContextId: String? {
        activeContext.map { type(of: $0).contextId }
    }

    /// Check if active context is persistent
    public var isActiveContextPersistent: Bool {
        activeContext?.isPersistent ?? false
    }

    /// Get all pinned contexts for prompt injection
    public func getPinnedContexts() -> [any ToolContext] {
        Array(pinnedContexts.values)
    }

    /// Get formatted pinned state for all pinned contexts
    public func formatPinnedStates() async -> String? {
        var states: [String] = []
        for context in pinnedContexts.values {
            if let state = await context.formatPinnedState() {
                states.append(state)
            }
        }
        return states.isEmpty ? nil : states.joined(separator: "\n\n")
    }
}
