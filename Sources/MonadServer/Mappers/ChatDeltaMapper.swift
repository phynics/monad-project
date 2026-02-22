import MonadCore
import MonadShared
import Foundation

/// Maps ChatEvent to MonadShared.ChatDelta for API responses
public struct ChatDeltaMapper {
    public static func mapEvent(_ event: ChatEvent) -> MonadShared.ChatDelta {
        switch event {
        case .generationContext(let metadata):
            return MonadShared.ChatDelta(type: .generationContext, metadata: metadata)

        case .delta(let content):
            return MonadShared.ChatDelta(type: .delta, content: content)

        case .thought(let content):
            return MonadShared.ChatDelta(type: .thought, thought: content)

        case .thoughtCompleted:
            return MonadShared.ChatDelta(type: .thoughtCompleted)

        case .toolCall(let toolCall):
            return MonadShared.ChatDelta(type: .toolCall, toolCalls: [toolCall])

        case .toolCallError(let id, let name, let error):
            return MonadShared.ChatDelta(
                type: .toolCallError,
                toolCallError: MonadShared.ToolCallErrorDelta(
                    toolCallId: id,
                    name: name,
                    error: error
                )
            )

        case .toolExecution(let id, let status):
            let (statusStr, name, target, resultStr) = mapToolExecutionStatus(status)
            return MonadShared.ChatDelta(
                type: .toolExecution,
                toolExecution: MonadShared.ToolExecutionDelta(
                    toolCallId: id,
                    status: statusStr,
                    name: name,
                    target: target,
                    result: resultStr
                )
            )

        case .generationCompleted(_, let meta):
            let apiMeta = MonadShared.APIMetadataDelta(
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
            return MonadShared.ChatDelta(type: .generationCompleted, responseMetadata: apiMeta)

        case .error(let error):
            if error is CancellationError {
                return MonadShared.ChatDelta(type: .generationCancelled)
            } else {
                return MonadShared.ChatDelta(type: .error, error: error.localizedDescription)
            }
        }
    }

    private static func mapToolExecutionStatus(_ status: ToolExecutionStatus) -> (status: String, name: String?, target: String?, result: String?) {
        switch status {
        case .attempting(let name, let ref):
            let target: String
            switch ref {
            case .known:
                target = "server"
            case .custom:
                target = "client"
            }
            return (status: "attempting", name: name, target: target, result: nil)

        case .success(let result):
            return (status: "success", name: nil, target: nil, result: result.output)

        case .failure(let error):
            return (status: "failure", name: nil, target: nil, result: error.localizedDescription)
        }
    }
}
