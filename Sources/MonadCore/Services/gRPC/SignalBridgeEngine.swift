import Foundation
import GRPC
import NIOCore
import SwiftProtobuf

public final class SignalBridgeEngine: Sendable {
    private let chatClient: MonadChatServiceAsyncClient
    private let sessionClient: MonadSessionServiceAsyncClient
    
    // In-memory mapping: Signal User ID -> Monad Session ID
    // Using a simple locked dictionary for thread safety if needed, 
    // but PoC is mostly sequential. Let's use an actor for state.
    private let state = SessionState()
    
    public init(channel: GRPCChannel) {
        self.chatClient = MonadChatServiceAsyncClient(channel: channel)
        self.sessionClient = MonadSessionServiceAsyncClient(channel: channel)
    }
    
    public func handleMessage(userId: String, content: String) async throws -> String {
        // 1. Get or Create Session
        let sessionId = try await getOrCreateSession(for: userId)
        
        // 2. Forward to Chat Service
        var request = MonadChatRequest()
        request.userQuery = content
        request.sessionID = sessionId
        
        let call = chatClient.makeChatStreamCall(request)
        
        var fullResponse = ""
        for try await response in call.responseStream {
            if case .contentDelta(let delta) = response.payload {
                fullResponse += delta
            }
        }
        
        return fullResponse
    }
    
    private func getOrCreateSession(for userId: String) async throws -> String {
        if let existing = await state.getSession(for: userId) {
            return existing
        }
        
        var sessionReq = MonadSession()
        sessionReq.id = UUID().uuidString
        sessionReq.title = "Signal Chat: \(userId)"
        sessionReq.tags = ["signal", userId]
        
        let created = try await sessionClient.createSession(sessionReq)
        await state.setSession(created.id, for: userId)
        return created.id
    }
    
    // Internal actor to manage mapping state
    private actor SessionState {
        private var userSessions: [String: String] = [:]
        
        func getSession(for userId: String) -> String? {
            userSessions[userId]
        }
        
        func setSession(_ sessionId: String, for userId: String) {
            userSessions[userId] = sessionId
        }
    }
}
