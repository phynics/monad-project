import Foundation
import Logging
import MonadShared
import OpenAI

extension ChatEngine {
    func executeTools(
        calls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam],
        availableTools: [AnyTool],
        turnCount: Int,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async -> (results: [ChatQuery.ChatCompletionMessageParam], requiresClientExecution: Bool, debugRecords: [ToolResultRecord]) {
        var executionResults: [ChatQuery.ChatCompletionMessageParam] = []
        var requiresClientExecution = false
        var debugRecords: [ToolResultRecord] = []

        for call in calls {
            let toolName = ANSIColors.colorize(call.function.name, color: ANSIColors.brightCyan)
            guard let tool = availableTools.first(where: { $0.id == call.function.name }) else {
                logger.error("Tool not found: \(toolName)")
                executionResults.append(.tool(.init(content: .textContent(.init("Error: Tool not found")), toolCallId: call.id)))
                continuation.yield(.toolCallError(toolCallId: call.id, name: call.function.name, error: "Tool not found: \(call.function.name)"))
                continue
            }

            // Emit attempting event so the CLI can show tool progress
            let toolRef = tool.toolReference
            continuation.yield(.toolProgress(toolCallId: call.id, status: .attempting(name: tool.name, reference: toolRef)))

            let argsData = call.function.arguments.data(using: .utf8) ?? Data()
            let argsDict = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]

            logger.info("Executing tool \(toolName)...")
            do {
                let result = try await tool.execute(parameters: argsDict)
                debugRecords.append(ToolResultRecord(toolCallId: call.id, name: call.function.name, output: result.output, turn: turnCount))
                if result.success {
                    logger.info("Tool \(toolName) succeeded")
                    continuation.yield(.toolCompleted(toolCallId: call.id, status: .success(result)))
                } else {
                    let errorMsg = result.error ?? "Unknown error"
                    logger.error("Tool \(toolName) failed: \(errorMsg)")
                    continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: errorMsg)))
                }
                executionResults.append(.tool(.init(content: .textContent(.init(result.output)), toolCallId: call.id)))
            } catch let error as ToolError {
                if case .clientExecutionRequired = error {
                    logger.info("Tool \(toolName) requires client execution")
                    requiresClientExecution = true
                    break
                }
                logger.error("Tool \(toolName) error: \(error.localizedDescription)")
                executionResults.append(.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)))
                continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: error.localizedDescription)))
            } catch {
                logger.error("Tool \(toolName) unexpected error: \(error.localizedDescription)")
                executionResults.append(.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)))
                continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: error.localizedDescription)))
            }
        }
        return (executionResults, requiresClientExecution, debugRecords)
    }
}
