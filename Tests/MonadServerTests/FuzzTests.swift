import Foundation
import Testing
import GRPC
import MonadCore
import MonadServerCore
import MonadTestSupport

@MainActor
@Suite struct FuzzTests {
    
    @Test("Fuzz: SessionHandler with malformed IDs")
    func testSessionHandlerFuzz() async throws {
        let persistence = MockPersistenceService()
        let handler = SessionHandler(persistence: persistence)
        let context = MockServerContext()
        
        let malformedIDs = ["", "invalid-uuid", "0000", "long-string-" + String(repeating: "a", count: 1000)]
        
        for id in malformedIDs {
            var req = MonadFetchSessionRequest()
            req.id = id
            
            // Should fail gracefully
            _ = try? await handler.fetchSession(request: req, context: context)
        }
    }
    
    @Test("Fuzz: ChatHandler with various inputs")
    func testChatHandlerFuzz() async throws {
        let persistence = MockPersistenceService()
        let llm = MockLLMService()
        let handler = ChatHandler(llm: llm, persistence: persistence)
        let context = MockServerContext()
        
        // 1. sendMessage with empty/large queries
        let queries = ["", String(repeating: "fuzz", count: 10000)]
        for query in queries {
            var req = MonadChatRequest()
            req.userQuery = query
            _ = try await handler.sendMessage(request: req, context: context)
        }
        
        // 2. generateTitle with empty message history
        var titleReq = MonadGenerateTitleRequest()
        titleReq.messages = []
        _ = try await handler.generateTitle(request: titleReq, context: context)
        
        // 3. generateTitle with malformed messages
        var malformedMsg = MonadMessage()
        malformedMsg.id = "not-a-uuid"
        titleReq.messages = [malformedMsg]
        _ = try await handler.generateTitle(request: titleReq, context: context)
    }
    
    @Test("Fuzz: NoteHandler with large content and malformed IDs")
    func testNoteHandlerFuzz() async throws {
        let persistence = MockPersistenceService()
        let handler = NoteHandler(persistence: persistence)
        let context = MockServerContext()
        
        // Large content
        var note = MonadNote()
        note.name = String(repeating: "n", count: 5000)
        note.content = String(repeating: "c", count: 100000)
        _ = try await handler.saveNote(request: note, context: context)
        
        // Delete with malformed ID
        var deleteReq = MonadDeleteNoteRequest()
        deleteReq.id = "invalid"
        _ = try? await handler.deleteNote(request: deleteReq, context: context)
    }

    @Test("Fuzz: MemoryHandler with malformed search requests")
    func testMemoryHandlerFuzz() async throws {
        let persistence = MockPersistenceService()
        let handler = MemoryHandler(persistence: persistence)
        let context = MockServerContext()
        
        // 1. Search with empty text
        var req = MonadSearchRequest()
        req.text = ""
        _ = try await handler.searchMemories(request: req, context: context)
        
        // 2. Search with empty/invalid vector
        var vectorReq = MonadSearchRequest()
        var vectorQuery = MonadEmbeddingQuery()
        vectorQuery.vector = [] // Empty
        vectorQuery.minSimilarity = -1.0 // Invalid similarity
        vectorReq.vector = vectorQuery
        _ = try await handler.searchMemories(request: vectorReq, context: context)
        
        // 3. Save memory with invalid data
        var mem = MonadMemory()
        mem.id = "garbage"
        mem.embedding = [Double.nan, Double.infinity]
        _ = try? await handler.saveMemory(request: mem, context: context)
    }

    @Test("Fuzz: JobHandler state transitions")
    func testJobHandlerFuzz() async throws {
        let persistence = MockPersistenceService()
        let handler = JobHandler(persistence: persistence)
        let context = MockServerContext()
        
        // 1. Dequeue from empty queue
        _ = try? await handler.dequeueNextJob(request: MonadEmpty(), context: context)
        
        // 2. Save job with missing fields
        let job = MonadJob() // All defaults
        _ = try await handler.saveJob(request: job, context: context)
        
        // 3. Delete non-existent job
        var deleteReq = MonadDeleteJobRequest()
        deleteReq.id = UUID().uuidString
        _ = try? await handler.deleteJob(request: deleteReq, context: context)
    }
}
