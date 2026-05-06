import Foundation
@testable import MonadCLI
import Testing

@Suite struct ChatSendPreflightTests {
    @Test("matching local and server agent can proceed")
    func matchingAgent_proceeds() {
        let agentId = UUID()
        #expect(ChatSendPreflight.evaluate(serverAttachedAgentId: agentId, localAgentId: agentId) == .proceed)
    }

    @Test("missing server agent aborts send")
    func missingServerAgent_aborts() {
        #expect(ChatSendPreflight.evaluate(serverAttachedAgentId: nil, localAgentId: UUID()) == .abortNoAttachedAgent)
    }

    @Test("server agent mismatch syncs local state")
    func mismatchedAgent_syncsToServer() {
        let serverAgentId = UUID()
        #expect(ChatSendPreflight.evaluate(serverAttachedAgentId: serverAgentId, localAgentId: UUID()) == .syncLocalAgent(serverAgentId))
    }
}
