import Foundation
import Logging

/// Error types for ToolExecutor
public enum ToolExecutorError: LocalizedError, Equatable {
    case toolNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool '\(name)' not found"
        }
    }
}

/// Result of tool execution including message and compactification node
public struct ToolExecutionResult: Sendable {
    /// The response message from the tool
    public let message: Message

    /// Compactification node for context compression (optional)
    public let compactificationNode: CompactificationNode?

    public init(message: Message, compactificationNode: CompactificationNode? = nil) {
        self.message = message
        self.compactificationNode = compactificationNode
    }
}

/// Executes tool calls and manages tool results
public actor ToolExecutor {
    private let toolManager: SessionToolManager
    private let logger = Logger.tools

    /// Active tool context session
    public let contextSession: ToolContextSession

    /// Reference to job queue for auto-dequeue functionality
    public let jobQueueContext: JobQueueContext?

    // Loop detection
    private var callCounts: [ToolCall: Int] = [:]
    private let maxRepeatedCalls = 3

    public init(
        toolManager: SessionToolManager,
        contextSession: ToolContextSession = ToolContextSession(),
        jobQueueContext: JobQueueContext? = nil
    ) {
        self.toolManager = toolManager
        self.contextSession = contextSession
        self.jobQueueContext = jobQueueContext
    }

    /// Reset loop detection state
    public func reset() {
        callCounts.removeAll()
    }

    /// Get a tool by ID
    public func getTool(id: String) async -> Tool? {
        return await toolManager.getTool(id: id)
    }

    /// Get all available tools
    public func getAvailableTools() async -> [any Tool] {
        return await toolManager.getEnabledTools()
    }

    /// Execute a single tool call
    public func execute(_ toolCall: ToolCall) async throws -> Message {
        // Loop detection check
        let count = callCounts[toolCall, default: 0] + 1
        callCounts[toolCall] = count

        if count >= maxRepeatedCalls {
            logger.warning("Loop detected for tool: \(toolCall.name)")
            return Message(
                content:
                    "Error: Loop detected. Tool '\(toolCall.name)' has been called \(count) times with the exact same parameters. Please try a different approach or verify your logic.",
                role: .tool,
                think: nil
            )
        }

        // Check for context auto-exit: if a context is active and this is NOT a context tool,
        // deactivate the context before proceeding
        let isContextTool = await contextSession.isContextTool(toolCall.name)
        let isGatewayForActiveContext = await contextSession.isActiveContextGateway(toolCall.name)

        if await contextSession.hasActiveContext && !isContextTool && !isGatewayForActiveContext {
            logger.info("Non-context tool called, deactivating active context")
            await contextSession.deactivate()
        }

        guard let tool = await toolManager.getTool(id: toolCall.name) else {
            logger.error("Tool not found: \(toolCall.name)")
            throw ToolExecutorError.toolNotFound(toolCall.name)
        }

        logger.info("Executing tool: \(tool.name)")

        // Convert [String: AnyCodable] to [String: Any] for tool execution
        var anyArgs: [String: Any] = [:]
        for (key, value) in toolCall.arguments {
            anyArgs[key] = value.value
        }

        do {
            let result = try await tool.execute(parameters: anyArgs)

            var responseContent: String
            if result.success {
                responseContent = result.output
            } else {
                let errorMsg = result.error ?? "Unknown error"
                responseContent = "Error: \(errorMsg)"
            }

            // Append context state if a context is active and this is a context tool
            if await contextSession.hasActiveContext && isContextTool,
                let context = await contextSession.activeContext
            {
                let contextState = await context.formatState()
                if !contextState.isEmpty {
                    responseContent += "\n\n---\n\(contextState)"
                }
            }

            if result.success {
                logger.info("Tool \(tool.name) executed successfully")
            } else {
                let errorDesc = result.error ?? "Unknown error"
                logger.error("Tool \(tool.name) failed: \(errorDesc)")
            }

            return Message(
                content: responseContent,
                role: .tool,
                think: nil,
                subagentContext: result.subagentContext
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

    /// Execute a tool call and generate a compactification summary
    /// - Parameters:
    ///   - toolCall: The tool call to execute
    ///   - assistantMessageId: ID of the assistant message that triggered this call
    /// - Returns: ToolExecutionResult containing message and optional compactification node
    public func executeWithSummary(_ toolCall: ToolCall, assistantMessageId: UUID) async throws
        -> ToolExecutionResult
    {
        let message = try await execute(toolCall)

        // Generate compactification node
        guard let tool = await toolManager.getTool(id: toolCall.name) else {
            return ToolExecutionResult(message: message)
        }

        // Convert arguments to [String: Any]
        var anyArgs: [String: Any] = [:]
        for (key, value) in toolCall.arguments {
            anyArgs[key] = value.value
        }

        // Create tool result for summarization
        let toolResult = ToolResult.success(message.content)
        let summary = tool.summarize(parameters: anyArgs, result: toolResult)

        let compactNode = CompactificationNode.toolExecution(
            toolName: toolCall.name,
            arguments: anyArgs,
            resultSummary: String(message.content.prefix(100)),
            callMessageId: assistantMessageId,
            responseMessageId: message.id
        )

        // Override summary with tool-specific one
        var node = compactNode
        node.summary = summary

        return ToolExecutionResult(message: message, compactificationNode: node)
    }

    /// Execute multiple tool calls concurrently
    public func executeAll(_ toolCalls: [ToolCall]) async -> [Message] {
        logger.debug("Executing \(toolCalls.count) tool calls concurrently")

        return await withTaskGroup(of: (Int, Message).self) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.execute(toolCall)
                        return (index, result)
                    } catch {
                        let errorMessage = Message(
                            content:
                                "Failed to execute tool \(toolCall.name): \(error.localizedDescription)",
                            role: .tool,
                            think: nil
                        )
                        return (index, errorMessage)
                    }
                }
            }

            var results: [(Int, Message)] = []
            for await result in group {
                results.append(result)
            }

            // Restore original order
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}
