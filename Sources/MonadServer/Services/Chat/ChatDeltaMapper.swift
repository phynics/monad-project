import MonadCore
import Foundation

public struct ChatDeltaMapper {
    public static func mapEvent(_ event: ChatEvent) -> ChatDelta {
        switch event {
        case .generationContext(let m):
            return ChatDelta(type: .generationContext, metadata: m)
        case .delta(let content):
            return ChatDelta(type: .delta, content: content)
        case .thought(let content):
            return ChatDelta(type: .thought, thought: content)
        case .thoughtCompleted:
            return ChatDelta(type: .thoughtCompleted)
        case .toolCall(let tc):
            return ChatDelta(type: .toolCall, toolCalls: [tc])
        case .toolCallError(let id, let name, let error):
            return ChatDelta(
                type: .toolCallError,
                toolCallError: ToolCallErrorDelta(
                    toolCallId: id,
                    name: name,
                    error: error
                )
            )
        case .toolExecution(let id, let status):
            let statusStr: String
            var name: String?
            var target: String?
            var resultStr: String?

            switch status {
            case .attempting(let n, let ref):
                statusStr = "attempting"
                name = n
                switch ref {
                case .known:
                    target = "server"
                case .custom:
                    target = "client"
                }
            case .success(let res):
                statusStr = "success"
                resultStr = res.output
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
        case .generationCompleted(_, let meta):
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
        case .error(let e):
            if e is CancellationError {
                return ChatDelta(type: .generationCancelled)
            } else {
                return ChatDelta(type: .error, error: e.localizedDescription)
            }
        }
    }
}
