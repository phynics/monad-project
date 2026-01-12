import Foundation
import Testing
import MonadCore
import GRPC
import NIOCore
import SwiftProtobuf
import OpenAI

@testable import MonadCore
@testable import MonadUI

@Suite(.serialized)
@MainActor
struct ChatViewModelgRPCTests {
    
    @Test("Test switching to Remote mode updates services")
    func testModeSwitching() async throws {
        let localLLM = LLMService(storage: ConfigurationStorage())
        let localPersistence = try await PersistenceService.create()
        let persistenceManager = PersistenceManager(persistence: localPersistence)
        let viewModel = ChatViewModel(llmService: localLLM, persistenceManager: persistenceManager)
        await viewModel.startup()
        
        // Initially local
        #expect(viewModel.llmService is LLMService)
        
        // Switch to remote
        var remoteConfig = LLMConfiguration.openAI
        remoteConfig.connectionMode = .remote
        remoteConfig.monadServer = MonadServerConfiguration(host: "localhost", port: 50051)
        
        try await viewModel.applyConfiguration(remoteConfig)
        
        #expect(viewModel.llmService is gRPCLLMService)
        #expect(persistenceManager.persistence is gRPCPersistenceService)
    }
    
    @Test("Test error handling in gRPCLLMService")
    func testgRPCErrorHandling() async throws {
        // Create a channel that will fail
        let group = NIOSingletons.posixEventLoopGroup
        let channel = try GRPCChannelPool.with(
            target: .host("nonexistent-host-name-that-fails", port: 50051),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )
        
        let gRPCService = gRPCLLMService(channel: channel)
        
        // Attempt to send message
        await #expect(throws: Error.self) {
            _ = try await gRPCService.sendMessage("Hello")
        }
        
        _ = channel.close()
    }
}
