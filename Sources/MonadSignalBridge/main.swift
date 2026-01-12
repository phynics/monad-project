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
        
        let engine = SignalBridgeEngine(channel: channel)
        
        print("Connected to MonadServer at localhost:50051")
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
            
            do {
                print("Monad [Processing...]")
                let response = try await engine.handleMessage(userId: userId, content: message)
                print("Monad [Assistant]: \(response)")
                print("Signal [Outgoing to \(userId)]: \(response)")
            } catch {
                print("Error: \(error.localizedDescription)")
            }
            
            print("\nWaiting for next message...")
        }
        
        _ = channel.close()
    }
}