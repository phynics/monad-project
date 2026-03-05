import Testing
import Foundation
import MonadTestSupport
@testable import MonadCore
import Dependencies

@Suite("Context Manager Mocking Tests")
struct ContextManagerMockingTests {
    
    @Test("Context Manager Initialization with Mocks")
    func testContextManagerInitializationWithMocks() async {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()

        let contextManager = withDependencies {
            $0.persistenceService = mockPersistence
            $0.embeddingService = mockEmbedding
        } operation: {
            ContextManager(workspace: nil)
        }

        #expect(contextManager != nil)
    }
}