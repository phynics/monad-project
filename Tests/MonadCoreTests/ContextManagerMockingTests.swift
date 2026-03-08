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
            $0.timelinePersistence = mockPersistence
            $0.workspacePersistence = mockPersistence
            $0.memoryStore = mockPersistence
            $0.messageStore = mockPersistence
            $0.agentTemplateStore = mockPersistence
            $0.backgroundJobStore = mockPersistence
            $0.clientStore = mockPersistence
            $0.toolPersistence = mockPersistence
            $0.agentInstanceStore = mockPersistence
            $0.embeddingService = mockEmbedding
        } operation: {
            ContextManager(workspace: nil)
        }

        // Just verifying initialization completes successfully
        _ = contextManager
    }
}