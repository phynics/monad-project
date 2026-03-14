import ErrorKit
import Foundation
import Logging
import MonadShared

/// Error types for ToolExecutor
public enum ToolExecutorError: Throwable, Equatable {
    case toolNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .toolNotFound(name):
            return "Tool '\(name)' not found"
        }
    }

    public var userFriendlyMessage: String {
        switch self {
        case let .toolNotFound(name):
            return "The assistant tried to use a tool named '\(name)', but it is not available in the current context."
        }
    }
}

/// Executes tool calls and manages tool results
public actor ToolExecutor {
    private let toolManager: TimelineToolManager
    private let logger = Logger.module(named: "tools")

    /// Active tool context session
    public let timelineContext: ToolTimelineContext

    /// Reference to job queue for auto-dequeue functionality
    public let jobQueueContext: BackgroundJobQueueContext?

    // Loop detection
    private var callCounts: [ToolCall: Int] = [:]
    private let maxRepeatedCalls = 3

    public init(
        toolManager: TimelineToolManager,
        timelineContext: ToolTimelineContext = ToolTimelineContext(),
        jobQueueContext: BackgroundJobQueueContext? = nil
    ) {
        self.toolManager = toolManager
        self.timelineContext = timelineContext
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
    public func getAvailableTools() async -> [AnyTool] {
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
        let isContextTool = await timelineContext.isContextTool(toolCall.name)
        let isGatewayForActiveContext = await timelineContext.isActiveContextGateway(toolCall.name)

        if await timelineContext.hasActiveContext && !isContextTool && !isGatewayForActiveContext {
            logger.info("Non-context tool called, deactivating active context")
            await timelineContext.deactivate()
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
            if await timelineContext.hasActiveContext && isContextTool,
               let context = await timelineContext.activeContext
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
                think: nil
            )
        } catch {
            let errMsg = ErrorKit.userFriendlyMessage(for: error)
            logger.error("Error executing tool \(tool.name): \(errMsg)")
            return Message(
                content: "Failed to execute tool \(tool.name): \(errMsg)",
                role: .tool,
                think: nil
            )
        }
    }

    /// Execute multiple tool calls, sequentially when a context is active to avoid races,
    /// concurrently otherwise.
    public func executeAll(_ toolCalls: [ToolCall]) async -> [Message] {
        logger.debug("Executing \(toolCalls.count) tool calls")

        // Context mutations (activate/deactivate) are not safe to interleave across concurrent
        // tasks. Fall back to sequential execution whenever a context is active.
        if await timelineContext.hasActiveContext {
            var messages: [Message] = []
            for toolCall in toolCalls {
                do {
                    try messages.append(await execute(toolCall))
                } catch {
                    messages.append(Message(
                        content: "Failed to execute tool \(toolCall.name): \(ErrorKit.userFriendlyMessage(for: error))",
                        role: .tool,
                        think: nil
                    ))
                }
            }
            return messages
        }

        return await withTaskGroup(of: (Int, Message).self) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.execute(toolCall)
                        return (index, result)
                    } catch {
                        let errorMessage = Message(
                            content: "Failed to execute tool \(toolCall.name): \(ErrorKit.userFriendlyMessage(for: error))",
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
