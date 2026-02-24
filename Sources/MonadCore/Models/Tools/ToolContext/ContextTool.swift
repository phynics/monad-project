import Foundation

// MARK: - Context Tool Marker

/// Marker protocol for tools that belong to a ToolContext.
/// Used for type identification and filtering.
public protocol ContextTool: Tool {
    /// The context ID this tool belongs to
    static var parentContextId: String { get }
}
