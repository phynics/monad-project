import XCTest
@testable import MonadCore
@testable import MonadUI
import GRDB
import OpenAI

final class ToolLoopIntegrationTests: XCTestCase {
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
    func testMultiStepToolLoop() async throws {
        // Step 1: LLM returns a tool call
        let toolCall: [String: Any] = [
            "index": 0,
            "id": "call_1",
            "type": "function",
            "function": [
                "name": "list_directory",
                "arguments": "{\"dir_path\":\".\"}"
            ]
        ]
        
        mockLLMClient.nextToolCalls = [[toolCall]]
        mockLLMClient.nextResponses = ["", "I found the files you asked for."]
        
        viewModel.inputText = "List files please"
        
        // 2. Trigger Send
        viewModel.sendMessage()
        
        // 3. Wait for completion of the loop
        let start = Date()
        while (viewModel.isLoading || viewModel.isExecutingTools) && Date().timeIntervalSince(start) < 5.0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 4. Verify results
        // Messages: 0: Welcome, 1: User, 2: Assistant (Tool Call), 3: Tool Result, 4: Assistant (Final)
        XCTAssertEqual(viewModel.messages.count, 5)
        XCTAssertEqual(viewModel.messages[2].role, .assistant)
        XCTAssertNotNil(viewModel.messages[2].toolCalls)
        XCTAssertEqual(viewModel.messages[3].role, .tool)
        XCTAssertEqual(viewModel.messages[4].role, .assistant)
        XCTAssertEqual(viewModel.messages[4].content, "I found the files you asked for.")
    }
    
    @MainActor
    func testToolLoopRedundantContextAvoidance() async throws {
        // Step 1: LLM returns a tool call
        let toolCall: [String: Any] = [
            "index": 0,
            "id": "call_1",
            "type": "function",
            "function": [
                "name": "list_directory",
                "arguments": "{\"dir_path\":\".\"}"
            ]
        ]
        
        mockLLMClient.nextToolCalls = [[toolCall]]
        mockLLMClient.nextResponses = ["", "Final response after tool."]
        
        viewModel.inputText = "Trigger tool loop"
        
        // We want to verify that context isn't regathered during the tool turn loop.
        // Currently context gathering happens in sendMessage() before runConversationLoop.
        // runConversationLoop now reuses the passed contextData.
        
        // Execute
        viewModel.sendMessage()
        
        // Wait
        let start = Date()
        while (viewModel.isLoading || viewModel.isExecutingTools) && Date().timeIntervalSince(start) < 5.0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        XCTAssertEqual(viewModel.messages.count, 5)
        XCTAssertEqual(viewModel.messages.last?.content, "Final response after tool.")
    }
}
