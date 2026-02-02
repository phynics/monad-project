import Foundation
import Logging

// MARK: - ToolContext Protocol

/// A scoped tool environment with its own state and tools.
///
/// ToolContexts are activated by gateway tools and provide additional
/// context-specific tools that are only available within the active context.
///
/// **Persistence Modes**:
/// - Non-persistent (default): Auto-deactivates when any non-context tool is called
/// - Persistent: Stays active even when other tools are called (e.g., document sessions)
///
/// **Pinning**: Pinned contexts inject their state into the LLM prompt even after deactivation,
/// ensuring the LLM has access to relevant context (e.g., open files, loaded documents).
public protocol ToolContext: AnyObject, Sendable {
    /// Unique identifier for this context type
    static var contextId: String { get }

    /// Human-readable name for the context
    static var displayName: String { get }

    /// Description of what this context provides
    static var contextDescription: String { get }

    /// Whether this context persists when other (non-context) tools are called.
    /// Default: false (auto-exits on non-context tool calls)
    var isPersistent: Bool { get }

    /// Whether this context's state should be "pinned" to the prompt.
    /// Pinned contexts contribute their state to formatToolsForPrompt even when not active.
    /// Useful for document/file contexts where the LLM needs ongoing awareness.
    var isPinned: Bool { get }

    /// Tools available only within this context
    var contextTools: [any Tool] { get async }

    /// Called when context is activated
    func activate() async

    /// Called when context is deactivated
    func deactivate() async

    /// Format current state for inclusion in tool output
    func formatState() async -> String

    /// Welcome message shown when context is activated
    func welcomeMessage() async -> String

    /// Format pinned state for inclusion in prompt (only used if isPinned is true)
    /// This is a condensed version of formatState for prompt injection
    func formatPinnedState() async -> String?
}

// MARK: - Default Implementations

extension ToolContext {
    /// Default: non-persistent (auto-exits on non-context tool calls)
    public var isPersistent: Bool { false }

    /// Default: not pinned
    public var isPinned: Bool { false }

    public func activate() async {
        // Default: no-op
    }

    public func deactivate() async {
        // Default: no-op
    }

    /// Default: no pinned state
    public func formatPinnedState() async -> String? {
        nil
    }

    public func welcomeMessage() async -> String {
        let tools = await contextTools
        let toolList = tools.map { "- `\($0.id)`: \($0.description)" }.joined(
            separator: "\n")

        let exitNote =
            isPersistent
            ? "This context persists across other tool calls."
            : "Calling any non-context tool will exit this context."

        return """
            \(Self.displayName) activated.

            Available commands:
            \(toolList)

            Note: \(exitNote)

            \(await formatState())
            """
    }
}

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
    public func getContextTools() async -> [any Tool] {
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

// MARK: - Context Tool Marker

/// Marker protocol for tools that belong to a ToolContext.
/// Used for type identification and filtering.
public protocol ContextTool: Tool {
    /// The context ID this tool belongs to
    static var parentContextId: String { get }
}
