import XCTest
import GRDB
import MonadCore
@testable import MonadUI
import Testing

@MainActor
final class SQLProxyTests: XCTestCase {
    var persistence: PersistenceService!
    var persistenceManager: PersistenceManager!
    var llmService: LLMService!
    var viewModel: ChatViewModel!
    
    override func setUp() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        persistenceManager = PersistenceManager(persistence: persistence)
        
        let mockEmbedding = MockEmbeddingService()
        llmService = LLMService(embeddingService: mockEmbedding)
        
        viewModel = ChatViewModel(llmService: llmService, persistenceManager: persistenceManager)
        
        // Wait for startup logic
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testSensitiveSQLTriggersConfirmation() async throws {
        // Setup a tool call that is sensitive (CREATE TABLE)
        let toolCall = ToolCall(name: "execute_sql", arguments: ["sql": AnyCodable("CREATE TABLE test (id INTEGER)")])
        
        // Execute through orchestrator
        // We need to simulate the delegate response. 
        // In the real app, ChatViewModel shows a dialog.
        
        // Let's verify the orchestrator calls the delegate.
        let mockDelegate = MockSQLConfirmationDelegate()
        viewModel.toolOrchestrator.delegate = mockDelegate
        
        _ = try await viewModel.toolOrchestrator.handleToolCalls([toolCall], assistantMsgId: UUID())
        
        XCTAssertTrue(mockDelegate.wasCalled)
        XCTAssertEqual(mockDelegate.lastSQL, "CREATE TABLE test (id INTEGER)")
    }
    
    func testNonSensitiveSQLDoesNotTriggerConfirmation() async throws {
        let toolCall = ToolCall(name: "execute_sql", arguments: ["sql": AnyCodable("SELECT * FROM note")])
        
        let mockDelegate = MockSQLConfirmationDelegate()
        viewModel.toolOrchestrator.delegate = mockDelegate
        
        _ = try await viewModel.toolOrchestrator.handleToolCalls([toolCall], assistantMsgId: UUID())
        
        XCTAssertFalse(mockDelegate.wasCalled)
    }
}

class MockSQLConfirmationDelegate: SQLConfirmationDelegate {
    var wasCalled = false
    var lastSQL: String?
    var response = true
    
    func requestConfirmation(for sql: String) async -> Bool {
        wasCalled = true
        lastSQL = sql
        return response
    }
}
