import Foundation
import OSLog
import Observation
import OpenAI

/// A tool that the LLM can call
protocol Tool: Sendable, PromptFormattable {
    /// Unique identifier for the tool
    var id: String { get }

    /// Display name for the tool
    var name: String { get }

    /// Description of what the tool does
    var description: String { get }

    /// Whether tool requires user permission to execute
    var requiresPermission: Bool { get }

    /// Example usage of the tool (optional, for prompt)
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
    var usageExample: String? { nil }

    /// Convert to OpenAI tool parameter
    func toToolParam() -> ChatQuery.ChatCompletionToolParam {
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
    var promptString: String {
        var parts: [String] = []

        // Title with permission marker
        let permMarker = requiresPermission ? " 🔒" : ""
        parts.append("**\(name)**\(permMarker)")

        // ID and description
        parts.append("- Tool ID: `\(id)`")
        parts.append("- Purpose: \(description)")

        // Usage example (if provided)
        if let example = usageExample {
            parts.append("- Example:")
            parts.append("  ```")
            parts.append("  \(example)")
            parts.append("  ```")
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - Array Extension (for concrete types and protocols)

/// Format multiple tools for prompt inclusion
func formatToolsForPrompt(_ tools: [any Tool]) async -> String {
    guard !tools.isEmpty else { return "" }

    var toolSpecs: [String] = []

    for tool in tools {
        guard await tool.canExecute() else { continue }
        toolSpecs.append(tool.promptString)
    }

    guard !toolSpecs.isEmpty else { return "" }

    return """
        You have access to these tools:

        \(toolSpecs.joined(separator: "\n\n"))

        **Usage Format:**
        For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
        ```xml
        <tool_call>
        {"name": "function_name", "arguments": {"param": "value"}}
        </tool_call>
        ```

        **Guidelines:**
        - Use tools when you need to search, create, or modify data
        - Wrap each tool call in <tool_call></tool_call> tags
        - Arguments must be a JSON object (not a string)
        - Be specific in your queries
        """
}

/// Result of tool execution
struct ToolResult {
    let success: Bool
    let output: String
    let error: String?

    static func success(_ output: String) -> ToolResult {
        ToolResult(success: true, output: output, error: nil)
    }

    static func failure(_ error: String) -> ToolResult {
        ToolResult(success: false, output: "", error: error)
    }
}

/// Tool configuration for a chat session
struct ToolConfiguration: Codable, Identifiable {
    let id: String
    var isEnabled: Bool

    init(toolId: String, isEnabled: Bool = true) {
        self.id = toolId
        self.isEnabled = isEnabled
    }
}

/// Session-specific tool settings
@Observable
class SessionToolManager {
    var enabledTools: Set<String> = []

    /// Available tools in the system
    private let availableTools: [Tool]

    init(availableTools: [Tool]) {
        self.availableTools = availableTools
        // Enable all tools by default
        self.enabledTools = Set(availableTools.map { $0.id })
    }

    /// Get tools that are currently enabled
    func getEnabledTools() -> [Tool] {
        availableTools.filter { enabledTools.contains($0.id) }
    }

    /// Toggle tool enabled state
    func toggleTool(_ toolId: String) {
        if enabledTools.contains(toolId) {
            enabledTools.remove(toolId)
        } else {
            enabledTools.insert(toolId)
        }
    }

    /// Get tool by ID
    func getTool(id: String) -> Tool? {
        availableTools.first { $0.id == id }
    }
}
