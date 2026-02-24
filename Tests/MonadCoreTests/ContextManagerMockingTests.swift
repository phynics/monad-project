import Testing
import Foundation
@testable import MonadCore

@Suite("Context Manager Mocking Tests")
struct ContextManagerMockingTests {
    
    @Test("Context Manager Initialization with Mocks")
    func testContextManagerInitializationWithMocks() async {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()

        let contextManager = ContextManager(
            persistenceService: mockPersistence,
            embeddingService: mockEmbedding,
            workspace: nil
        )

        #expect(contextManager != nil)
    }
}