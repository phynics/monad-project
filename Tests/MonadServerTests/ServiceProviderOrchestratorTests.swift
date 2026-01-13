import Foundation
import Testing
import MonadCore
import MonadTestSupport
@testable import MonadServerCore

@MainActor
@Suite struct ServiceProviderOrchestratorTests {
    
    final class MockProvider: ServiceProvider, @unchecked Sendable {
        let name: String
        var isStarted = false
        var isShutdown = false
        
        init(name: String) {
            self.name = name
        }
        
        func start() async throws {
            isStarted = true
        }
        
        func shutdown() async throws {
            isShutdown = true
        }
    }
    
    @Test("Test orchestrator startup sequence")
    func testStartup() async throws {
        let persistence = MockPersistenceService()
        let llm = MockLLMService()
        let provider1 = MockProvider(name: "P1")
        let provider2 = MockProvider(name: "P2")
        
        let orchestrator = ServiceProviderOrchestrator(
            persistence: persistence,
            llm: llm,
            additionalProviders: [provider1, provider2]
        )
        
        try await orchestrator.startup()
        
        #expect(provider1.isStarted)
        #expect(provider2.isStarted)
    }
    
    @Test("Test orchestrator shutdown sequence")
    func testShutdown() async throws {
        let persistence = MockPersistenceService()
        let llm = MockLLMService()
        let provider = MockProvider(name: "P1")
        
        let orchestrator = ServiceProviderOrchestrator(
            persistence: persistence,
            llm: llm,
            additionalProviders: [provider]
        )
        
        try await orchestrator.shutdown()
        #expect(provider.isShutdown)
    }
}
