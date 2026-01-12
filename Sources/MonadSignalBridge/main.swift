import Foundation
import GRPC
import NIOCore
import NIOPosix
import MonadCore

@main
struct MonadSignalBridge {
    static func main() async throws {
        print("Monad Signal Bridge (PoC) starting...")
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        // 1. Setup gRPC connection to MonadServer
        let channel = try GRPCChannelPool.with(
            target: .host("localhost", port: 50051),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )
        
        let chatClient = MonadChatServiceAsyncClient(channel: channel)
        let sessionClient = MonadSessionServiceAsyncClient(channel: channel)
        
        print("Connected to MonadServer at localhost:50051")
        
        // In-memory mapping: Signal User ID -> Monad Session ID
        var userSessions: [String: String] = [:]
        
        // 2. PoC: Simulate Signal Message Loop with multiple users
        print("Waiting for simulated Signal messages... Format: '<user_id>: <message>'")
        
        while let line = readLine() {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else {
                print("Invalid format. Use '<user_id>: <message>'")
                continue
            }
            
            let userId = parts[0]
            let message = parts[1]
            
            print("Signal [User \(userId)]: \(message)")
            
            // 3. Session Management
            let sessionId: String
            if let existing = userSessions[userId] {
                sessionId = existing
            } else {
                print("Creating new session for User \(userId)...")
                var sessionReq = MonadSession()
                sessionReq.id = UUID().uuidString
                sessionReq.title = "Signal Chat: \(userId)"
                sessionReq.tags = ["signal", userId]
                
                do {
                    let created = try await sessionClient.createSession(sessionReq)
                    sessionId = created.id
                    userSessions[userId] = sessionId
                    print("New Monad Session: \(sessionId)")
                } catch {
                    print("Failed to create session on server: \(error.localizedDescription)")
                    continue
                }
            }
            
            // 4. Forward to gRPC
            var request = MonadChatRequest()
            request.userQuery = message
            request.sessionID = sessionId
            
            print("Monad [Thinking...]")
            
            let call = chatClient.makeChatStreamCall(request)
            
            var fullResponse = ""
            do {
                for try await response in call.responseStream {
                    if case .contentDelta(let delta) = response.payload {
                        fullResponse += delta
                    }
                }
                print("Monad [Assistant]: \(fullResponse)")
                print("Signal [Outgoing to \(userId)]: \(fullResponse)")
            } catch {
                print("Error from MonadServer: \(error.localizedDescription)")
            }
            
            print("\nWaiting for next message...")
        }
        
        _ = channel.close()
    }
}
