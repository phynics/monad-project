import Foundation

enum ChatSendPreflightDecision: Equatable {
    case proceed
    case syncLocalAgent(UUID)
    case abortNoAttachedAgent
}

enum ChatSendPreflight {
    static func evaluate(serverAttachedAgentId: UUID?, localAgentId: UUID?) -> ChatSendPreflightDecision {
        guard let serverAttachedAgentId else {
            return .abortNoAttachedAgent
        }

        if serverAttachedAgentId == localAgentId {
            return .proceed
        }

        return .syncLocalAgent(serverAttachedAgentId)
    }
}
