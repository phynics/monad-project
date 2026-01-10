import Foundation
import OSLog
import Observation
import OpenAI

/// A tool that the LLM can call
public protocol Tool: Sendable, PromptFormattable {
    /// Unique identifier for the tool
    var id: String { get }

    /// Display name for the tool
    var name: String { get }

    /// Description of what the tool does
    var description: String { get }

    /// Whether tool requires user permission to execute
    var requiresPermission: Bool { get }

    /// Example usage of the tool (optional, used for error guidance)
    var usageExample: String? { get }

    /// Whether tool can be used (e.g., readonly notes can't be edited)
    func canExecute() async -> Bool

    /// JSON schema for the tool's parameters
    var parametersSchema: [String: Any] { get }

    /// Execute the tool with given parameters
    func execute(parameters: [String: Any]) async throws -> ToolResult

    /// Convert to OpenAI tool parameter
    func toToolParam() -> ChatQuery.ChatCompletionToolParam
}

// MARK: - Default Implementation

extension Tool {
    /// Default: no usage example
    public var usageExample: String? { nil }

    /// Convert to OpenAI tool parameter
    public func toToolParam() -> ChatQuery.ChatCompletionToolParam {
        // Convert [String: Any] parametersSchema to JSONSchema using JSONSerialization/Decoder
        let schema: JSONSchema
        if let data = try? JSONSerialization.data(withJSONObject: parametersSchema),
            let decoded = try? JSONDecoder().decode(JSONSchema.self, from: data)
        {
            schema = decoded
        } else {
            // Fallback to empty object if conversion fails
            schema = .object([:])
        }

        return .init(
            function: .init(
                name: id,
                description: description,
                parameters: schema
            )
        )
    }
}

// MARK: - Prompt Formatting

extension Tool {
    /// Formatted content for inclusion in LLM prompt
    public var promptString: String {
        "- `\(id)`: \(description)"
    }
}

// MARK: - Array Extension (for concrete types and protocols)

/// Format multiple tools for prompt inclusion
public func formatToolsForPrompt(_ tools: [any Tool]) async -> String {
    guard !tools.isEmpty else { return "" }

    var toolSpecs: [String] = []

    for tool in tools {
        guard await tool.canExecute() else { continue }
        toolSpecs.append(tool.promptString)
    }

    guard !toolSpecs.isEmpty else { return "" }

    return """
        Available tools:
        \(toolSpecs.joined(separator: "\n"))

        Usage: Wrap JSON tool calls in <tool_call> tags:
        <tool_call>{"name": "tool_id", "arguments": {...}}</tool_call>

        Rules:
        - Use tools only for missing context.
        - Create memories frequently via `create_memory`.
        - `launch_subagent` for isolated tasks (no tools in subagents).
        - Prefer `load_document` over `cat`.
        - If a tool call fails, you can attempt to recover by correcting the parameters and trying again.
        - Be specific.
        """
}

/// Result of tool execution
public struct ToolResult: Sendable {
    public let success: Bool
    public let output: String
    public let error: String?
    public let subagentContext: SubagentContext?

    public static func success(_ output: String, subagentContext: SubagentContext? = nil)
        -> ToolResult
    {
        ToolResult(success: true, output: output, error: nil, subagentContext: subagentContext)
    }

    public static func failure(_ error: String) -> ToolResult {
        ToolResult(success: false, output: "", error: error, subagentContext: nil)
    }
}

/// Tool configuration for a chat session
public struct ToolConfiguration: Codable, Identifiable, Sendable {
    public let id: String
    public var isEnabled: Bool

    public init(toolId: String, isEnabled: Bool = true) {
        self.id = toolId
        self.isEnabled = isEnabled
    }
}

/// Session-specific tool settings
@Observable
@MainActor
public final class SessionToolManager {
    public var enabledTools: Set<String> = []

    /// Available tools in the system
    public let availableTools: [Tool]

    /// Context session for dynamic tool injection
    public var contextSession: ToolContextSession?

    public init(availableTools: [Tool], contextSession: ToolContextSession? = nil) {
        self.availableTools = availableTools
        self.contextSession = contextSession
        // Enable all tools by default
        self.enabledTools = Set(availableTools.map { $0.id })
    }

    /// Get tools that are currently enabled, including context tools if a context is active
    public func getEnabledTools() -> [Tool] {
        var tools = availableTools.filter { enabledTools.contains($0.id) }

        // Include context tools if a context is active
        if let session = contextSession, session.hasActiveContext {
            tools.append(contentsOf: session.getContextTools())
        }

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

    /// Get tool by ID (checks both regular tools and context tools)
    public func getTool(id: String) -> Tool? {
        // First check regular tools
        if let tool = availableTools.first(where: { $0.id == id }) {
            return tool
        }

        // Then check context tools if a context is active
        if let session = contextSession, session.hasActiveContext {
            return session.getContextTools().first { $0.id == id }
        }

        return nil
    }
}
