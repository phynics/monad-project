import MonadShared
import Foundation
import Logging
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

    /// Generate a compact summary of the tool execution for context compression
    /// - Parameters:
    ///   - parameters: The parameters used for execution
    ///   - result: The result of execution
    /// - Returns: A compact summary string, e.g. "[read_file(path)] → 45 lines"
    func summarize(parameters: [String: Any], result: ToolResult) -> String

    /// Convert to OpenAI tool parameter
    func toToolParam() -> ChatQuery.ChatCompletionToolParam
    
    /// Type-erase to AnyTool
    func toAnyTool() -> AnyTool
}

// MARK: - Default Implementation

extension Tool {
    /// Default: no usage example
    public var usageExample: String? { nil }

    /// Default summarize implementation - generates compact description
    public func summarize(parameters: [String: Any], result: ToolResult) -> String {
        // Extract key parameter values (max 3, truncated)
        let paramSummary = parameters.keys.sorted().prefix(3).compactMap { key -> String? in
            guard let value = parameters[key] else { return nil }
            let valueStr = String(describing: value).prefix(20)
            return "\(key)=\(valueStr)"
        }.joined(separator: ", ")

        // Truncate result
        let resultSummary: String
        if result.success {
            let lines = result.output.components(separatedBy: .newlines).count
            if lines > 1 {
                resultSummary = "\(lines) lines"
            } else {
                resultSummary = String(result.output.prefix(50))
            }
        } else {
            resultSummary = "error: \(result.error?.prefix(30) ?? "unknown")"
        }

        return "[\(id)(\(paramSummary))] → \(resultSummary)"
    }

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
    
    /// Type-erase to AnyTool
    public func toAnyTool() -> AnyTool {
        AnyTool(self)
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
public func formatToolsForPrompt(_ tools: [AnyTool]) async -> String {
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

        Rules:
        - Use tools only for missing context.
        - Create memories frequently via `create_memory`.
        - `launch_subagent` for isolated tasks.
        - Summarize the result if it is excessively long.
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

// MARK: - Type-Erased Tool

/// A type-erased wrapper around any `Tool` conformance.
///
/// Use `AnyTool` when you need to store tools in a concrete type context
/// (e.g., arrays, dictionaries) without `any Tool` existential boxing.
///
///     let tool: AnyTool = AnyTool(myReadFileTool)
///     let result = try await tool.execute(parameters: ["path": "/tmp/file.txt"])
///
public struct AnyTool: Tool {
    private let wrapped: any Tool

    public init(_ tool: any Tool) {
        self.wrapped = tool
    }

    public var id: String { wrapped.id }
    public var name: String { wrapped.name }
    public var description: String { wrapped.description }
    public var requiresPermission: Bool { wrapped.requiresPermission }
    public var usageExample: String? { wrapped.usageExample }
    public var parametersSchema: [String: Any] { wrapped.parametersSchema }

    public func canExecute() async -> Bool {
        await wrapped.canExecute()
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        try await wrapped.execute(parameters: parameters)
    }

    public func summarize(parameters: [String: Any], result: ToolResult) -> String {
        wrapped.summarize(parameters: parameters, result: result)
    }

    public func toToolParam() -> ChatQuery.ChatCompletionToolParam {
        wrapped.toToolParam()
    }
    
    /// Returns the ToolReference for this tool, used when emitting .toolExecution(.attempting) events.
    /// Downcasts to DelegatingTool to get the real reference; falls back to .known(id:) for other tools.
    public var toolReference: ToolReference {
        if let delegating = wrapped as? DelegatingTool {
            return delegating.ref
        }
        return .known(id: id)
    }
}
