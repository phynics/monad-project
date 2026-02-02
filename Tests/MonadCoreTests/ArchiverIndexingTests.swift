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
        let mockEmbedding = MockEmbeddingService()
        mockEmbedding.useDistinctEmbeddings = true
        
        // Initialize and configure to make it valid
        llmService = LLMService(embeddingService: mockEmbedding)
        var config = LLMConfiguration.openAI
        config.providers[.openAI]?.apiKey = "test-key"
        try await llmService.updateConfiguration(config)
        
        // ContextManager for archiver
        let contextManager = ContextManager(persistenceService: persistence, embeddingService: mockEmbedding)
        
        archiver = ConversationArchiver(
            persistence: persistence,
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
        try await archiver.archive(messages: messages, sessionId: persistenceManager.currentSession?.id, vacuumPolicy: .skip)
        
        // Verify messages saved in DB
        let sessions = try await persistence.fetchAllSessions(includeArchived: true)
        XCTAssertEqual(sessions.count, 1)
        let sessionId = sessions[0].id
        
        let savedMessages = try await persistence.fetchMessages(for: sessionId)
        XCTAssertEqual(savedMessages.count, 2)
        
        // Verify memories were created (indexing)
        let memories = try await persistence.fetchAllMemories()
        XCTAssertEqual(memories.count, 2)
        
        let contents = memories.map { $0.content }
        XCTAssertTrue(contents.contains("I want to learn about SwiftUI"))
        XCTAssertTrue(contents.contains("SwiftUI is a declarative framework"))
    }
    
    @MainActor
    func testArchiveGeneratesDescriptiveTitle() async throws {
        let mockClient = MockLLMClient()
        mockClient.nextResponse = "SwiftUI Learning Journey"
        
        let mockEmbedding = MockEmbeddingService()
        let customLLMService = LLMService(embeddingService: mockEmbedding, utilityClient: mockClient)
        
        // Configure customLLMService
        var config = LLMConfiguration.openAI
        config.providers[.openAI]?.apiKey = "test-key"
        try await customLLMService.updateConfiguration(config)
        // Manually set utility client again since updateConfiguration recreates clients from config
        await customLLMService.setClients(main: mockClient, utility: mockClient, fast: mockClient)
        
        let customArchiver = ConversationArchiver(
            persistence: persistence,
            llmService: customLLMService,
            contextManager: ContextManager(persistenceService: persistence, embeddingService: mockEmbedding)
        )
        
        let messages = [
            Message(content: "I want to learn SwiftUI", role: .user)
        ]
        
        let newSessionId = try await customArchiver.archive(messages: messages, sessionId: nil)
        
        let session = try await persistence.fetchSession(id: newSessionId)
        XCTAssertEqual(session?.title, "SwiftUI Learning Journey")
    }
}