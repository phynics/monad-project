import Foundation
import Testing
import MonadCore
import MonadTestSupport
import GRPC
import NIOCore
import NIOPosix
import SwiftProtobuf
import OpenAI
import GRDB

@testable import MonadCore
import MonadTestSupport
@testable import MonadUI

@Suite(.serialized)
@MainActor
struct DistributedIntegrationTests {
    
    @Test("Test multi-client shared state interaction")
    func testMultiClientSharedState() async throws {
        let group = NIOSingletons.posixEventLoopGroup
        
        // 1. Setup shared server-side state
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
        let serverPersistence = PersistenceService(dbQueue: dbQueue)
        let serverLLM = MockLLMService()
        serverLLM.nextResponse = "Shared state response"
        
        // 2. Start in-process gRPC server
        let server = try await Server.insecure(group: group)
            .withServiceProviders([
                ChatHandler(llm: serverLLM, persistence: serverPersistence),
                SessionHandler(persistence: serverPersistence),
                MemoryHandler(persistence: serverPersistence),
                NoteHandler(persistence: serverPersistence),
                JobHandler(persistence: serverPersistence)
            ])
            .bind(host: "localhost", port: 0) // OS selects port
            .get()
        
        let port = server.channel.localAddress!.port!
        
        // 3. Setup Client 1: Main Client (ChatViewModel)
        let channel = try GRPCChannelPool.with(
            target: .host("localhost", port: port),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )
        
        let localLLM = LLMService()
        let localPersistence = try await PersistenceService.create()
        let persistenceManager = PersistenceManager(persistence: localPersistence)
        let viewModel = ChatViewModel(llmService: localLLM, persistenceManager: persistenceManager)
        await viewModel.startup()
        
        // Switch Main Client to Remote mode
        var remoteConfig = LLMConfiguration.openAI
        remoteConfig.connectionMode = .remote
        remoteConfig.monadServer = MonadServerConfiguration(host: "localhost", port: port)
        try await viewModel.applyConfiguration(remoteConfig)
        
        // 4. Setup Client 2: Second Client (Another ChatViewModel)
        let localLLM2 = LLMService()
        let localPersistence2 = try await PersistenceService.create()
        let persistenceManager2 = PersistenceManager(persistence: localPersistence2)
        let viewModel2 = ChatViewModel(llmService: localLLM2, persistenceManager: persistenceManager2)
        await viewModel2.startup()
        try await viewModel2.applyConfiguration(remoteConfig)
        
        // 5. Execution: Second client creates a session
        let secondClientSessionId = UUID()
        var session = ConversationSession(id: secondClientSessionId, title: "Second Client Session")
        try await persistenceManager2.persistence.saveSession(session)
        
        // 6. Execution: Main client should be able to see the session created by Second client
        await viewModel.checkStartupState()
        #expect(persistenceManager.activeSessions.contains { $0.id == secondClientSessionId })
        
        // Cleanup
        _ = channel.close()
        try await server.close().get()
    }
}
