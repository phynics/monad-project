import Foundation
import MonadShared

/// Events emitted during the context gathering process
public enum ContextGatheringEvent: Sendable {
    case progress(Message.ContextGatheringProgress)
    case complete(ContextData)
}
