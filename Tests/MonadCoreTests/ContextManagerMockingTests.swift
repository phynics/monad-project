import Testing
import Foundation
import MonadTestSupport
@testable import MonadCore
@testable import MonadShared
@testable import MonadShared
import Dependencies

@Suite("Context Manager Mocking Tests")
struct ContextManagerMockingTests {
    
    @Test("Context Manager Initialization with Mocks")
    func testContextManagerInitializationWithMocks() async {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()

        let contextManager = try await withDependencies {
            $0.persistenceService = mockPersistence
            $0.embeddingService = mockEmbedding
        } operation: {
            ContextManager(workspace: nil)
        }

        // Just verifying initialization completes successfully
        _ = contextManager
    }
}