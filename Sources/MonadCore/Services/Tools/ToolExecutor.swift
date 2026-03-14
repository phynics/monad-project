import ErrorKit
import Foundation
import Logging
import MonadShared

/// Executes tool calls and manages tool results.
public actor ToolExecutor {
    private let toolManager: TimelineToolManager
    private let logger = Logger.module(named: "tools")

    /// Active tool context session
    public let timelineContext: ToolTimelineContext

    /// Maximum times the same tool call (same name + arguments) is allowed before loop detection
    /// fires. Note: `ToolCall.==` compares `name` and `arguments` only — calls with *different*
    /// arguments are counted separately.
    private let maxRepeatedCalls: Int

    /// Loop detection state
    private var callCounts: [ToolCall: Int] = [:]

    public init(
        toolManager: TimelineToolManager,
        timelineContext: ToolTimelineContext = ToolTimelineContext(),
        maxRepeatedCalls: Int = 3
    ) {
        self.toolManager = toolManager
        self.timelineContext = timelineContext
        self.maxRepeatedCalls = maxRepeatedCalls
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

    /// Execute a single tool call. Always returns a `Message`; errors are surfaced as tool
    /// messages so the LLM can observe and recover from failures.
    public func execute(_ toolCall: ToolCall) async -> Message {
        // Loop detection
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

        // Check for context auto-exit: if a context is active and this is NOT a context tool,
        // deactivate the context before proceeding.
        let isContextTool = await timelineContext.isContextTool(toolCall.name)
        let isGatewayForActiveContext = await timelineContext.isActiveContextGateway(toolCall.name)

        if await timelineContext.hasActiveContext && !isContextTool && !isGatewayForActiveContext {
            logger.info("Non-context tool called, deactivating active context")
            await timelineContext.deactivate()
        }

        guard let tool = await toolManager.getTool(id: toolCall.name) else {
            logger.error("Tool not found: \(toolCall.name)")
            return Message(
                content: "Error: Tool '\(toolCall.name)' is not available.",
                role: .tool,
                think: nil
            )
        }

        logger.info("Executing tool: \(tool.name)")

        let anyArgs = toolCall.arguments.toAnyDictionary

        do {
            let result = try await tool.execute(parameters: anyArgs)

            let responseContent: String
            if result.success {
                logger.info("Tool \(tool.name) executed successfully")
                responseContent = result.output
            } else {
                let errorMsg = result.error ?? "Unknown error"
                logger.error("Tool \(tool.name) failed: \(errorMsg)")
                responseContent = "Error: \(errorMsg)"
            }

            // Append context state if a context is active and this is a context tool.
            var finalContent = responseContent
            if await timelineContext.hasActiveContext && isContextTool,
               let context = await timelineContext.activeContext
            {
                let contextState = await context.formatState()
                if !contextState.isEmpty {
                    finalContent += "\n\n---\n\(contextState)"
                }
            }

            return Message(content: finalContent, role: .tool, think: nil)
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
                messages.append(await execute(toolCall))
            }
            return messages
        }

        // Note: execute() is actor-isolated, so concurrent tasks serialise at the actor boundary.
        // withTaskGroup is used here for efficient result collection and to restore original order.
        return await withTaskGroup(of: (Int, Message).self) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask {
                    let result = await self.execute(toolCall)
                    return (index, result)
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
