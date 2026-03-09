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
            let outcome = await executeSingleTool(
                call: call,
                availableTools: availableTools,
                turnCount: turnCount,
                continuation: continuation
            )

            if outcome.requiresClientExecution {
                requiresClientExecution = true
                break
            }

            executionResults.append(outcome.message)
            if let record = outcome.debugRecord {
                debugRecords.append(record)
            }
        }
        return (executionResults, requiresClientExecution, debugRecords)
    }

    private func executeSingleTool(
        call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam,
        availableTools: [AnyTool],
        turnCount: Int,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async -> (message: ChatQuery.ChatCompletionMessageParam, debugRecord: ToolResultRecord?, requiresClientExecution: Bool) {
        let toolName = ANSIColors.colorize(call.function.name, color: ANSIColors.brightCyan)
        guard let tool = availableTools.first(where: { $0.id == call.function.name }) else {
            logger.error("Tool not found: \(toolName)")
            continuation.yield(.toolCallError(toolCallId: call.id, name: call.function.name, error: "Tool not found: \(call.function.name)"))
            return (.tool(.init(content: .textContent(.init("Error: Tool not found")), toolCallId: call.id)), nil, false)
        }

        // Emit attempting event so the CLI can show tool progress
        let toolRef = tool.toolReference
        continuation.yield(.toolProgress(toolCallId: call.id, status: .attempting(name: tool.name, reference: toolRef)))

        let argsData = call.function.arguments.data(using: .utf8) ?? Data()
        let argsDict = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]

        logger.info("Executing tool \(toolName)...")
        do {
            let result = try await tool.execute(parameters: argsDict)
            let debugRecord = ToolResultRecord(toolCallId: call.id, name: call.function.name, output: result.output, turn: turnCount)
            if result.success {
                logger.info("Tool \(toolName) succeeded")
                continuation.yield(.toolCompleted(toolCallId: call.id, status: .success(result)))
            } else {
                let errorMsg = result.error ?? "Unknown error"
                logger.error("Tool \(toolName) failed: \(errorMsg)")
                continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: errorMsg)))
            }
            return (.tool(.init(content: .textContent(.init(result.output)), toolCallId: call.id)), debugRecord, false)
        } catch let error as ToolError {
            if case .clientExecutionRequired = error {
                logger.info("Tool \(toolName) requires client execution")
                return (.tool(.init(content: .textContent(.init("")), toolCallId: call.id)), nil, true)
            }
            logger.error("Tool \(toolName) error: \(error.localizedDescription)")
            continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: error.localizedDescription)))
            return (.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)), nil, false)
        } catch {
            logger.error("Tool \(toolName) unexpected error: \(error.localizedDescription)")
            continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: error.localizedDescription)))
            return (.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)), nil, false)
        }
    }
}
