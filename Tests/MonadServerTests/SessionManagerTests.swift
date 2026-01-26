import Testing
import Foundation
@testable import MonadServerCore
import MonadCore

@Suite struct SessionManagerTests {
    
    @Test("Test Session Creation and Context Manager Access")
    func testSessionCreation() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding)
        
        let session = await sessionManager.createSession()
        
        #expect(session.id != UUID.init(), "Session should have an ID")
        
        let retrievedSession = await sessionManager.getSession(id: session.id)
        #expect(retrievedSession != nil, "Should be able to retrieve created session")
        #expect(retrievedSession?.id == session.id)
        
        // This fails because ContextManager support is not implemented
        let contextManager = await sessionManager.getContextManager(for: session.id)
        #expect(contextManager != nil, "ContextManager should be created for session")
    }
    
    @Test("Test Stale Session Cleanup")
    func testCleanup() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding)
        
        let session = await sessionManager.createSession()
        
        // Simulate time passing (need a way to set last active time in SessionManager, maybe via internal method or by updating Session struct)
        // For now, check if cleanup method exists
        await sessionManager.cleanupStaleSessions(maxAge: 0) // Should remove immediately if maxAge is 0
        
        let retrieved = await sessionManager.getSession(id: session.id)
        #expect(retrieved == nil, "Session should be cleaned up")
    }
}
