import XCTest
@testable import MonadCore
@testable import MonadUI
import GRDB
import OpenAI

final class ChatViewModelRetryTests: XCTestCase {
    var persistence: PersistenceService!
    var persistenceManager: PersistenceManager!
    var llmService: LLMService!
    var viewModel: ChatViewModel!
    
    @MainActor
    override func setUp() async throws {
        let queue = try DatabaseQueue()
        persistence = PersistenceService(dbQueue: queue)
        persistenceManager = PersistenceManager(persistence: persistence)
        
        let mockEmbedding = MockEmbeddingService()
        llmService = LLMService(embeddingService: mockEmbedding)
        
        viewModel = ChatViewModel(llmService: llmService, persistenceManager: persistenceManager)
        
        // Wait for startup logic
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    
    @MainActor
    func testRetryLogic() async throws {
        // 1. Setup a state with an error and some messages
        viewModel.messages = [
            Message(content: "Initial query", role: .user),
            Message(content: "First answer", role: .assistant),
            Message(content: "Query to retry", role: .user)
        ]
        viewModel.errorMessage = "Simulated error"
        
        // 2. Add an extra failed message that should be removed on retry
        viewModel.messages.append(Message(content: "Broken partial response", role: .assistant))
        
        // 3. Trigger retry
        viewModel.retry()
        
        // 4. Verify state immediately after retry call
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(viewModel.messages.count, 3) // Broken message removed
        XCTAssertEqual(viewModel.messages.last?.content, "Query to retry")
    }
}
