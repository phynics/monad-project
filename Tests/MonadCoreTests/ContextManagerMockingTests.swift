import MonadShared
import XCTest
import MonadCore

final class ContextManagerMockingTests: XCTestCase {
    func testContextManagerInitializationWithMocks() async {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()

        // This should fail to compile because ContextManager expects PersistenceService (concrete)
        let contextManager = ContextManager(
            persistenceService: mockPersistence,
            embeddingService: mockEmbedding
        )

        XCTAssertNotNil(contextManager)
    }
}
