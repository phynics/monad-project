import Foundation

/// A type that can be formatted for inclusion in an LLM prompt.
public protocol PromptFormattable: Sendable {
    /// The formatted string representation of this object for a prompt.
    var promptString: String { get }
}

import Logging

// MARK: - ToolContext Protocol

/// A scoped tool environment with its own state and tools.
///
/// ToolContexts are activated by gateway tools and provide additional
/// context-specific tools that are only available within the active context.
///
/// **Persistence Modes**:
/// - Non-persistent (default): Auto-deactivates when any non-context tool is called
/// - Persistent: Stays active even when other tools are called (e.g., job queues)
///
/// **Pinning**: Pinned contexts inject their state into the LLM prompt even after deactivation,
/// ensuring the LLM has access to relevant context (e.g., loaded metadata or state).
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
    /// Useful for contexts where the LLM needs ongoing awareness.
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
