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
            // Fetch session should fail with invalidArgument or notFound, but NOT crash
            var req = MonadFetchSessionRequest()
            req.id = id
            
            do {
                _ = try await handler.fetchSession(request: req, context: context)
            } catch let error as GRPCStatus {
                #expect(error.code == .invalidArgument || error.code == .notFound)
            } catch {
                // Other errors are acceptable as long as they aren't crashes
            }
        }
    }
    
    @Test("Fuzz: ChatHandler with empty/large queries")
    func testChatHandlerFuzz() async throws {
        let persistence = MockPersistenceService()
        let llm = MockLLMService()
        let handler = ChatHandler(llm: llm, persistence: persistence)
        let context = MockServerContext()
        
        let queries = ["", String(repeating: "fuzz", count: 10000)]
        
        for query in queries {
            var req = MonadChatRequest()
            req.userQuery = query
            
            // Should not crash
            _ = try await handler.sendMessage(request: req, context: context)
        }
    }
    
    @Test("Fuzz: NoteHandler with large content")
    func testNoteHandlerFuzz() async throws {
        let persistence = MockPersistenceService()
        let handler = NoteHandler(persistence: persistence)
        let context = MockServerContext()
        
        var note = MonadNote()
        note.name = String(repeating: "n", count: 5000)
        note.content = String(repeating: "c", count: 100000)
        
        // Should not crash
        _ = try await handler.saveNote(request: note, context: context)
    }
}
