import Foundation
import GRDB
import MonadCore
@testable import MonadUI
import Testing

@MainActor
@Suite(.serialized)
struct SQLProxyTests {
    private let persistence: PersistenceService
    private let persistenceManager: PersistenceManager
    private let llmService: LLMService
    private let viewModel: ChatViewModel
    
    init() async throws {
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

    @Test("Test sensitive SQL triggers confirmation")
    func sensitiveSQLTriggersConfirmation() async throws {
        // Setup a tool call that is sensitive (CREATE TABLE)
        let toolCall = ToolCall(name: "execute_sql", arguments: ["sql": AnyCodable("CREATE TABLE test (id INTEGER)")])
        
        // Let's verify the orchestrator calls the delegate.
        let mockDelegate = MockSQLConfirmationDelegate()
        
        // Re-inject tool with delegate into manager
        let sqlTool = ExecuteSQLTool(persistenceService: persistence, confirmationDelegate: mockDelegate)
        viewModel.toolManager.updateAvailableTools([sqlTool])
        
        _ = try await viewModel.toolOrchestrator.handleToolCalls([toolCall], assistantMsgId: UUID())
        
        #expect(mockDelegate.wasCalled)
        #expect(mockDelegate.lastSQL == "CREATE TABLE test (id INTEGER)")
    }

    @Test("Test non-sensitive SQL does not trigger confirmation")
    func nonSensitiveSQLDoesNotTriggerConfirmation() async throws {
        let toolCall = ToolCall(name: "execute_sql", arguments: ["sql": AnyCodable("SELECT * FROM note")])
        
        let mockDelegate = MockSQLConfirmationDelegate()
        
        let sqlTool = ExecuteSQLTool(persistenceService: persistence, confirmationDelegate: mockDelegate)
        viewModel.toolManager.updateAvailableTools([sqlTool])
        
        _ = try await viewModel.toolOrchestrator.handleToolCalls([toolCall], assistantMsgId: UUID())
        
        #expect(!mockDelegate.wasCalled)
    }

    @Test("Test user cancellation of sensitive SQL")
    func userCancellationOfSensitiveSQL() async throws {
        let toolCall = ToolCall(name: "execute_sql", arguments: ["sql": AnyCodable("DROP TABLE note")])
        
        let mockDelegate = MockSQLConfirmationDelegate()
        mockDelegate.response = false // Simulate cancel
        
        let sqlTool = ExecuteSQLTool(persistenceService: persistence, confirmationDelegate: mockDelegate)
        viewModel.toolManager.updateAvailableTools([sqlTool])
        
        let results = try await viewModel.toolExecutor.execute(toolCall)
        
        #expect(mockDelegate.wasCalled)
        #expect(results.content.contains("User cancelled"))
    }
}

class MockSQLConfirmationDelegate: SQLConfirmationDelegate, @unchecked Sendable {
    var wasCalled = false
    var lastSQL: String?
    var response = true
    
    func requestConfirmation(for sql: String) async -> Bool {
        wasCalled = true
        lastSQL = sql
        return response
    }
}
