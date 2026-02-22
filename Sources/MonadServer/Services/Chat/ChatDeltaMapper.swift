import MonadShared
import MonadCore
import Foundation

public struct ChatDeltaMapper {
    public static func mapEvent(_ event: ChatEvent) -> MonadShared.ChatDelta {
        switch event {
        case .generationContext(let m):
            return MonadShared.ChatDelta(type: .generationContext, metadata: m)
        case .delta(let content):
            return MonadShared.ChatDelta(type: .delta, content: content)
        case .thought(let content):
            return MonadShared.ChatDelta(type: .thought, thought: content)
        case .thoughtCompleted:
            return MonadShared.ChatDelta(type: .thoughtCompleted)
        case .toolCall(let tc):
            return MonadShared.ChatDelta(type: .toolCall, toolCalls: [tc])
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
        case .error(let e):
            if e is CancellationError {
                return MonadShared.ChatDelta(type: .generationCancelled)
            } else {
                return MonadShared.ChatDelta(type: .error, error: e.localizedDescription)
            }
        }
    }
}
