import XCTest
@testable import MonadCore
import MonadTestSupport
@testable import MonadUI
import GRDB
import OpenAI

final class ChatViewModelStateTests: XCTestCase {
    var persistence: PersistenceService!
    var persistenceManager: PersistenceManager!
    var mockLLMClient: MockLLMClient!
    var llmService: LLMService!
    var viewModel: ChatViewModel!
    
    @MainActor
    override func setUp() async throws {
        let queue = try DatabaseQueue()
        
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        
        persistence = PersistenceService(dbQueue: queue)
        persistenceManager = PersistenceManager(persistence: persistence)
        
        mockLLMClient = MockLLMClient()
        let mockEmbedding = MockEmbeddingService()
        llmService = LLMService(embeddingService: mockEmbedding, client: mockLLMClient)
        
        viewModel = ChatViewModel(llmService: llmService, persistenceManager: persistenceManager)
        await viewModel.startup()
        
        // Wait for startup logic
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    
    @MainActor
    func testSendMessageStateTransitions() async throws {
        // 1. Initial State
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.messages.count, 1) // Welcome message
        
        // 2. Mock Setup
        mockLLMClient.nextResponse = "Hello user!"
        viewModel.inputText = "Hi assistant"
        
        // 3. Trigger Send
        viewModel.sendMessage()
        
        // 3. Verifying Loading State
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        
        // 4. Wait for completion
        // The viewModel uses a Task for sendMessage, so we need to wait
        let start = Date()
        while viewModel.isLoading && Date().timeIntervalSince(start) < 2.0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        // 5. Final State
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage, "ErrorMessage should be nil but got: \(viewModel.errorMessage ?? "none")")
        // It seems it might have more than 2 messages if tool calls or something happened?
        // Let's check what the messages are.
        if viewModel.messages.count != 3 {
            for (i, m) in viewModel.messages.enumerated() {
                print("DEBUG: Message \(i): \(m.role) - \(m.content)")
            }
        }
        // Messages: 0: Welcome, 1: User, 2: Assistant
        XCTAssertEqual(viewModel.messages.count, 3)
        XCTAssertEqual(viewModel.messages.last?.content, "Hello user!")
    }
    
    @MainActor
    func testSendMessageFailureStateTransitions() async throws {
        // Setup mock to fail
        mockLLMClient.shouldThrowError = true
        viewModel.inputText = "Trigger error"
        
        XCTAssertNil(viewModel.errorMessage)
        
        // Trigger Send
        viewModel.sendMessage()
        
        // Wait for completion
        let start = Date()
        while viewModel.isLoading && Date().timeIntervalSince(start) < 5.0 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // Final State
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        print("DEBUG: Error message received: \(viewModel.errorMessage ?? "nil")")
        XCTAssertTrue(viewModel.errorMessage?.lowercased().contains("failure") == true || viewModel.errorMessage?.lowercased().contains("error") == true)
    }
}
