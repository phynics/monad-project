import MonadCore
import MonadShared
import Foundation

public struct ChatDeltaMapper {
    public static func mapEvent(_ event: ChatEvent) -> ChatDelta {
        switch event {
        case .meta(let meta):
            switch meta {
            case .generationContext(let metadata):
                return ChatDelta(type: .generationContext, metadata: metadata)
            case .generationCompleted(_, let meta):
                return mapGenerationCompleted(meta)
            }

        case .delta(let delta):
            switch delta {
            case .thinking(let content):
                return ChatDelta(type: .thought, thought: content)

            case .generation(let content):
                return ChatDelta(type: .delta, content: content)
            case .toolCall(let tc):
                return ChatDelta(type: .toolCall, toolCalls: [tc])
            case .toolExecution(let id, let status):
                return mapToolExecution(id: id, status: status)
            }

        case .error(let err):
            switch err {
            case .toolCallError(let id, let name, let error):
                return ChatDelta(
                    type: .toolCallError,
                    toolCallError: ToolCallErrorDelta(
                        toolCallId: id,
                        name: name,
                        error: error
                    )
                )
            case .error(let error):
                if error is CancellationError {
                    return ChatDelta(type: .generationCancelled)
                } else {
                    return ChatDelta(type: .error, error: error.localizedDescription)
                }
            }

        case .completion(let completion):
            switch completion {
            case .generationCompleted(_, let meta):
                return mapGenerationCompleted(meta)
            case .toolExecution(let id, let status):
                return mapToolExecution(id: id, status: status)
            }
        }
    }

    // MARK: - Helpers

    private static func mapGenerationCompleted(_ meta: APIResponseMetadata) -> ChatDelta {
        let apiMeta = APIMetadataDelta(
            model: meta.model,
            promptTokens: meta.promptTokens,
            completionTokens: meta.completionTokens,
            totalTokens: meta.totalTokens,
            finishReason: meta.finishReason,
            systemFingerprint: meta.systemFingerprint,
            duration: meta.duration,
            tokensPerSecond: meta.tokensPerSecond,
            debugSnapshotData: meta.debugSnapshotData
        )
        return ChatDelta(type: .generationCompleted, responseMetadata: apiMeta)
    }

    private static func mapToolExecution(id: String, status: ToolExecutionStatus) -> ChatDelta {
        let statusStr: String
        var name: String?
        var target: String?
        var resultStr: String?

        switch status {
        case .attempting(let toolName, let ref):
            statusStr = "attempting"
            name = toolName
            switch ref {
            case .known:
                target = "server"
            case .custom:
                target = "client"
            }
        case .success(let res):
            statusStr = "success"
            resultStr = res.output
        case .failed(_, let error):
            statusStr = "failure"
            resultStr = "Error: \(error)"
        case .failure(let err):
            statusStr = "failure"
            resultStr = err.localizedDescription
        }

        return ChatDelta(
            type: .toolExecution,
            toolExecution: ToolExecutionDelta(
                toolCallId: id,
                status: statusStr,
                name: name,
                target: target,
                result: resultStr
            )
        )
    }
}
