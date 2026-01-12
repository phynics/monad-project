import Foundation
import Testing
import MonadCore
import GRPC
import NIOCore
import SwiftProtobuf

@testable import MonadCore

@Suite
struct MonadServerTests {
    
    @Test("Test SessionHandler Logic")
    func testSessionHandlerLogic() async throws {
        let persistence = MockPersistenceService()
        let handler = SessionHandler(persistence: persistence)
        
        let id = UUID()
        let session = ConversationSession(id: id, title: "Test Session")
        try await persistence.saveSession(session)
        
        let context = MockServerContext()
        
        // Fetch all
        let empty = MonadEmpty()
        let list = try await handler.fetchAllSessions(request: empty, context: context)
        #expect(list.sessions.count == 1)
        #expect(list.sessions[0].title == "Test Session")
        
        // Fetch one
        var fetchReq = MonadFetchSessionRequest()
        fetchReq.id = id.uuidString
        let fetched = try await handler.fetchSession(request: fetchReq, context: context)
        #expect(fetched.id == id.uuidString)
        
        // Create
        var newSession = MonadSession()
        newSession.id = UUID().uuidString
        newSession.title = "New"
        let created = try await handler.createSession(request: newSession, context: context)
        #expect(created.title == "New")
        #expect(persistence.sessions.count == 2)
    }
    
    @Test("Test NoteHandler Logic")
    func testNoteHandlerLogic() async throws {
        let persistence = MockPersistenceService()
        let handler = NoteHandler(persistence: persistence)
        let context = MockServerContext()
        
        var note = MonadNote()
        note.id = UUID().uuidString
        note.name = "Test Note"
        note.content = "Content"
        
        let saved = try await handler.saveNote(request: note, context: context)
        #expect(saved.name == "Test Note")
        #expect(persistence.notes.count == 1)
        
        let list = try await handler.fetchAllNotes(request: MonadEmpty(), context: context)
        #expect(list.notes.count == 1)
    }
    
    @Test("Test JobHandler Logic")
    func testJobHandlerLogic() async throws {
        let persistence = MockPersistenceService()
        let handler = JobHandler(persistence: persistence)
        let context = MockServerContext()
        
        var job = MonadJob()
        job.id = UUID().uuidString
        job.title = "Test Job"
        job.status = .pending
        
        let saved = try await handler.saveJob(request: job, context: context)
        #expect(saved.title == "Test Job")
        
        let next = try await handler.dequeueNextJob(request: MonadEmpty(), context: context)
        #expect(next.id == job.id)
    }
    
    @Test("Test MemoryHandler Logic")
    func testMemoryHandlerLogic() async throws {
        let persistence = MockPersistenceService()
        let handler = MemoryHandler(persistence: persistence)
        let context = MockServerContext()
        
        var memory = MonadMemory()
        memory.id = UUID().uuidString
        memory.title = "Memory"
        memory.content = "Content"
        
        let saved = try await handler.saveMemory(request: memory, context: context)
        #expect(saved.title == "Memory")
        
        var searchReq = MonadSearchRequest()
        searchReq.text = "Mem"
        let results = try await handler.searchMemories(request: searchReq, context: context)
        #expect(results.results.count == 1)
    }
}