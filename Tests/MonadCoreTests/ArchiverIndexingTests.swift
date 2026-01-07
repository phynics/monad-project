import XCTest
@testable import MonadCore
@testable import MonadUI
import GRDB

final class ArchiverIndexingTests: XCTestCase {
    var persistence: PersistenceService!
    var persistenceManager: PersistenceManager!
    var archiver: ConversationArchiver!
    var llmService: LLMService!
    
    @MainActor
    override func setUp() async throws {
        let queue = try DatabaseQueue()
        
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        
        persistence = PersistenceService(dbQueue: queue)
        try await queue.write { db in
            try DatabaseSchema.createDefaultNotes(in: db)
        }
        
        persistenceManager = PersistenceManager(persistence: persistence)
        
        // We need an actual LLMService or a good mock.
        // LLMService needs embedding service.
        let mockEmbedding = MockEmbeddingService()
        llmService = LLMService(embeddingService: mockEmbedding)
        
        // ContextManager for archiver
        let contextManager = ContextManager(persistenceService: persistence, embeddingService: mockEmbedding)
        
        archiver = ConversationArchiver(
            persistenceManager: persistenceManager,
            llmService: llmService,
            contextManager: contextManager
        )
        
        try await persistenceManager.createNewSession(title: "Test Session")
    }
    
    @MainActor
    func testArchiveIndexesUserAndAssistantMessages() async throws {
        let messages = [
            Message(content: "I want to learn about SwiftUI", role: .user),
            Message(content: "SwiftUI is a declarative framework", role: .assistant)
        ]
        
        // Perform archiving
        try await archiver.archive(messages: messages)
        
        // Verify messages saved in DB
        // Let's fetch all sessions and check the last one
        let sessions = try await persistence.fetchAllSessions(includeArchived: true)
        XCTAssertEqual(sessions.count, 1)
        let sessionId = sessions[0].id
        
        let savedMessages = try await persistence.fetchMessages(for: sessionId)
        XCTAssertEqual(savedMessages.count, 2)
        
        // Verify memories were created (indexing)
        let memories = try await persistence.fetchAllMemories()
        // Should have indexed both user and assistant messages
        XCTAssertEqual(memories.count, 2)
        
        let contents = memories.map { $0.content }
        XCTAssertTrue(contents.contains("I want to learn about SwiftUI"))
        XCTAssertTrue(contents.contains("SwiftUI is a declarative framework"))
        
        // Verify memoryId link
        XCTAssertNotNil(savedMessages[0].memoryId)
        XCTAssertNotNil(savedMessages[1].memoryId)
    }
}
