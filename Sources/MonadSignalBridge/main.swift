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
        
        print("Connected to MonadServer at localhost:50051")
        
        // 2. PoC: Simulate Signal Message Loop
        print("Waiting for simulated Signal messages... (Type a message and press Enter)")
        
        while let line = readLine() {
            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty else { continue }
            
            print("Signal [User]: \(input)")
            
            // Forward to gRPC
            var request = MonadChatRequest()
            request.userQuery = input
            request.sessionID = UUID().uuidString
            
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
                print("Signal [Outgoing]: \(fullResponse)")
            } catch {
                print("Error from MonadServer: \(error.localizedDescription)")
            }
            
            print("\nWaiting for next message...")
        }
        
        _ = channel.close()
    }
}