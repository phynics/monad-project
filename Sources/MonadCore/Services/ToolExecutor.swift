import Foundation
import OSLog

/// Executes tool calls and manages tool results
@MainActor
public final class ToolExecutor {
    private let toolManager: SessionToolManager
    private let logger = Logger.tools
    
    // Loop detection
    private var callCounts: [ToolCall: Int] = [:]
    private let maxRepeatedCalls = 3

    public init(toolManager: SessionToolManager) {
        self.toolManager = toolManager
    }
    
    /// Reset loop detection state
    public func reset() {
        callCounts.removeAll()
    }

    /// Execute a single tool call
    public func execute(_ toolCall: ToolCall) async throws -> Message {
        // Loop detection check
        let count = callCounts[toolCall, default: 0] + 1
        callCounts[toolCall] = count
        
        if count >= maxRepeatedCalls {
            logger.warning("Loop detected for tool: \(toolCall.name)")
            return Message(
                content: "Error: Loop detected. Tool '\(toolCall.name)' has been called \(count) times with the exact same parameters. Please try a different approach or verify your logic.",
                role: .tool,
                think: nil
            )
        }

        guard let tool = toolManager.getTool(id: toolCall.name) else {
            logger.error("Tool not found: \(toolCall.name)")
            return Message(
                content: "Error: Tool '\(toolCall.name)' not found",
                role: .tool,
                think: nil
            )
        }

        logger.info("Executing tool: \(tool.name)")

        // Convert [String: AnyCodable] to [String: Any] for tool execution
        var anyArgs: [String: Any] = [:]
        for (key, value) in toolCall.arguments {
            anyArgs[key] = value.value
        }

        do {
            let result = try await tool.execute(parameters: anyArgs)
            let responseContent =
                result.success
                ? result.output
                : "Error: \(result.error ?? "Unknown error")"

            if result.success {
                logger.info("Tool \(tool.name) executed successfully")
            } else {
                logger.error("Tool \(tool.name) failed: \(result.error ?? "Unknown error")")
            }

            return Message(
                content: responseContent,
                role: .tool,
                think: nil
            )
        } catch {
            logger.error("Error executing tool \(tool.name): \(error.localizedDescription)")
            return Message(
                content: "Failed to execute tool \(tool.name): \(error.localizedDescription)",
                role: .tool,
                think: nil
            )
        }
    }

    /// Execute multiple tool calls sequentially
    public func executeAll(_ toolCalls: [ToolCall]) async -> [Message] {
        logger.debug("Executing \(toolCalls.count) tool calls sequentially")
        var results: [Message] = []

        for toolCall in toolCalls {
            do {
                let result = try await execute(toolCall)
                results.append(result)
            } catch {
                let errorMessage = Message(
                    content:
                        "Failed to execute tool \(toolCall.name): \(error.localizedDescription)",
                    role: .tool,
                    think: nil
                )
                results.append(errorMessage)
            }
        }

        return results
    }
}
