import Foundation
import MonadCore

public actor SessionManager {
    private var sessions: [UUID: ConversationSession] = [:]
    private var contextManagers: [UUID: ContextManager] = [:]
    private let persistenceService: any PersistenceServiceProtocol
    private let embeddingService: any EmbeddingService
    
    public init(persistenceService: any PersistenceServiceProtocol, embeddingService: any EmbeddingService) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
    }
    
    public func createSession(title: String = "New Conversation") async throws -> ConversationSession {
        let session = ConversationSession(id: UUID(), title: title)
        sessions[session.id] = session
        
        let contextManager = ContextManager(persistenceService: persistenceService, embeddingService: embeddingService)
        contextManagers[session.id] = contextManager
        
        // Ensure session exists in database for foreign key constraints
        try await persistenceService.saveSession(session)
        
        return session
    }
    
    public func getSession(id: UUID) -> ConversationSession? {
        guard var session = sessions[id] else { return nil }
        session.updatedAt = Date()
        sessions[id] = session
        return session
    }
    
    public func getContextManager(for sessionId: UUID) -> ContextManager? {
        return contextManagers[sessionId]
    }
    
    public func deleteSession(id: UUID) {
        sessions.removeValue(forKey: id)
        contextManagers.removeValue(forKey: id)
    }
    
    public func getHistory(for sessionId: UUID) async throws -> [Message] {
        let conversationMessages = try await persistenceService.fetchMessages(for: sessionId)
        return conversationMessages.map { $0.toMessage() }
    }
    
    public func getPersistenceService() -> any PersistenceServiceProtocol {
        return persistenceService
    }
    
    public func cleanupStaleSessions(maxAge: TimeInterval) {
        let now = Date()
        let staleIds = sessions.values.filter { session in
            return now.timeIntervalSince(session.updatedAt) > maxAge
        }.map { $0.id }
        
        for id in staleIds {
            deleteSession(id: id)
        }
    }
}
