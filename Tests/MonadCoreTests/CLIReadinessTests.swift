import XCTest
@testable import MonadCore
import MonadTestSupport
import GRDB

@MainActor
final class CLIReadinessTests: XCTestCase {
    var persistence: PersistenceService!
    var contextManager: ContextManager!
    var embeddingService: MockEmbeddingService!
    
    override func setUp() async throws {
        // 1. In-memory database for CLI/Testing
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        
        persistence = PersistenceService(dbQueue: queue)
        
        // 2. Mock Embedding
        embeddingService = MockEmbeddingService()
        
        // 3. Context Manager (Core)
        contextManager = ContextManager(persistenceService: persistence, embeddingService: embeddingService)
        
        // Setup default notes
        try await queue.write { db in
            try DatabaseSchema.createDefaultNotes(in: db)
        }
    }
    
    func testHeadlessContextGathering() async throws {
        let query = "How do I build a CLI?"
        
        // Execute context gathering (Core function)
        let context = try await contextManager.gatherContext(for: query)
        
        // Verify we got notes (default notes exist)
        XCTAssertFalse(context.notes.isEmpty, "Should retrieve default notes")
        
        // Check performance metrics
        XCTAssertGreaterThan(context.executionTime, 0)
    }
    
    func testHeadlessArchiving() async throws {
        let archiver = ConversationArchiver(
            persistence: persistence,
            llmService: LLMService(embeddingService: embeddingService),
            contextManager: contextManager
        )
        
        let messages = [
            Message(content: "Hi", role: .user),
            Message(content: "Hello", role: .assistant)
        ]
        
        // Archive a new session
        let sessionId = try await archiver.archive(messages: messages, sessionId: nil, vacuumPolicy: .skip)
        
        // Verify persistence
        let session = try await persistence.fetchSession(id: sessionId)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.isArchived, true)
        
        let savedMessages = try await persistence.fetchMessages(for: sessionId)
        XCTAssertEqual(savedMessages.count, 2)
    }
    
    func testPromptBuilderForCLI() async throws {
        let llmService = LLMService(embeddingService: embeddingService)
        
        // Simulate CLI conversation history
        let userQuery = "User input"
        let messages = [
            Message(content: userQuery, role: .user)
        ]
        
        // 1. Gather context first (CLI workflow)
        let context = try await contextManager.gatherContext(for: userQuery)
        
        // 2. Build prompt (Core function) using gathered context
        // Note: We map SemanticSearchResult to Memory for the prompt builder
        let (messagesParam, rawPrompt, _) = await llmService.buildPrompt(
            userQuery: userQuery,
            contextNotes: context.notes,
            documents: [], // No documents in this test
            memories: context.memories.map { $0.memory },
            chatHistory: messages,
            tools: []
        )
        
        XCTAssertFalse(rawPrompt.isEmpty)
        // Check that messages param is populated (System + User)
        XCTAssertGreaterThan(messagesParam.count, 0)
        
        // Ensure system prompt contains retrieved notes
        // The rawPrompt usually contains the system prompt content
        XCTAssertTrue(rawPrompt.contains("System")) // Default System note name
    }
}
