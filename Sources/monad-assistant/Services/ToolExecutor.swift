import Foundation
import os.log

/// Executes tool calls and manages tool results
@MainActor
class ToolExecutor {
    private let toolManager: SessionToolManager

    init(toolManager: SessionToolManager) {
        self.toolManager = toolManager
    }

    /// Execute a single tool call
    func execute(_ toolCall: ToolCall) async throws -> Message {
        guard let tool = toolManager.getTool(id: toolCall.name) else {
            Logger.ui.error("Tool not found: \(toolCall.name)")
            return Message(
                content: "Error: Tool '\(toolCall.name)' not found",
                role: .tool,
                think: nil
            )
        }

        // Check permissions
        if tool.requiresPermission {
            Logger.ui.info("Tool \(tool.name) requires permission")
            // TODO: Implement permission UI
        }

        // Convert [String: String] to [String: Any] for tool execution
        var anyArgs: [String: Any] = [:]
        for (key, value) in toolCall.arguments {
            anyArgs[key] = value
        }

        do {
            let result = try await tool.execute(parameters: anyArgs)
            let responseContent =
                result.success
                ? result.output
                : "Error: \(result.error ?? "Unknown error")"

            return Message(
                content: responseContent,
                role: .tool,
                think: nil
            )
        } catch {
            return Message(
                content: "Failed to execute tool \(tool.name): \(error.localizedDescription)",
                role: .tool,
                think: nil
            )
        }
    }

    /// Execute multiple tool calls sequentially
    func executeAll(_ toolCalls: [ToolCall]) async -> [Message] {
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
