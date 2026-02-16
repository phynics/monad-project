import MonadShared
import Foundation
import OpenAI

/// Protocol for defining tools that can be called by the AI
public protocol ToolDefinition {
    /// The name of the tool
    static var name: String { get }
    
    /// Description of what the tool does
    static var description: String { get }
    
    /// JSON Schema for the tool's parameters
    static var parametersSchema: JSONSchema { get }
    
    /// Execute the tool with the given arguments
    func execute(arguments: [String: Any]) async throws -> String
}

/// Helper for converting tool definitions to OpenAI format
public struct ToolConverter {
    public static func convert(_ tool: ToolDefinition.Type) -> ChatQuery.ChatCompletionToolParam {
        let function = ChatQuery.ChatCompletionToolParam.FunctionDefinition(
            name: tool.name,
            description: tool.description,
            parameters: tool.parametersSchema
        )
        
        return ChatQuery.ChatCompletionToolParam(function: function)
    }
}

// MARK: - Example Tool Definitions

/// Example: Get current time
public struct GetCurrentTimeTool: ToolDefinition {
    public static let name = "get_current_time"
    public static let description = "Get the current time in a specific timezone"
    public static let parametersSchema: JSONSchema = .init(
        .type(.object),
        .properties([
            "timezone": .init(
                .type(.string),
                .description("The timezone identifier (e.g., 'America/New_York', 'UTC')")
            )
        ]),
        .required(["timezone"])
    )
    
    public init() {}
    
    public func execute(arguments: [String: Any]) async throws -> String {
        guard let timezone = arguments["timezone"] as? String else {
            throw ToolError.missingArgument("timezone")
        }
        
        guard let tz = TimeZone(identifier: timezone) else {
            throw ToolError.invalidArgument("Invalid timezone identifier")
        }
        
        let formatter = DateFormatter()
        formatter.timeZone = tz
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return formatter.string(from: Date())
    }
}

/// Example: Calculate math expression
public struct CalculatorTool: ToolDefinition {
    public static let name = "calculator"
    public static let description = "Evaluate a mathematical expression"
    public static let parametersSchema: JSONSchema = .init(
        .type(.object),
        .properties([
            "expression": .init(
                .type(.string),
                .description("The mathematical expression to evaluate (e.g., '2 + 2', '10 * 5')")
            )
        ]),
        .required(["expression"])
    )
    
    public init() {}
    
    public func execute(arguments: [String: Any]) async throws -> String {
        guard let expression = arguments["expression"] as? String else {
            throw ToolError.missingArgument("expression")
        }
        
        // Simple calculator using NSExpression
        let expr = NSExpression(format: expression)
        if let result = expr.expressionValue(with: nil, context: nil) {
            return "\(result)"
        } else {
            throw ToolError.executionFailed("Failed to evaluate expression")
        }
    }
}

// MARK: - Calculator Tool
