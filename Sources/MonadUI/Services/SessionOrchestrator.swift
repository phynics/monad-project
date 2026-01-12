import Foundation
import MonadCore
import OSLog

/// Orchestrates session-level transitions and metadata generation.
@MainActor
public final class SessionOrchestrator {
    private let persistenceManager: PersistenceManager
    private let llmService: any LLMServiceProtocol
    private let logger = Logger(subsystem: "com.monad.ui", category: "SessionOrchestrator")
    
    public init(
        persistenceManager: PersistenceManager,
        llmService: any LLMServiceProtocol
    ) {
        self.persistenceManager = persistenceManager
        self.llmService = llmService
    }
    
    /// Checks the startup state and loads the latest session or creates a new one.
    /// Returns true if a welcome message should be added.
    public func checkStartupState() async throws -> Bool {
        if let latest = try await persistenceManager.fetchLatestSession() {
            try await persistenceManager.loadSession(id: latest.id)
            return persistenceManager.uiMessages.isEmpty
        } else {
            try await persistenceManager.createNewSession()
            return true
        }
    }
    
    /// Starts a new session, optionally deleting the old one.
    public func startNewSession(deleteOld: Bool) async throws {
        if deleteOld, let session = persistenceManager.currentSession {
            try await persistenceManager.deleteSession(id: session.id)
        }
        try await persistenceManager.createNewSession()
    }
    
    /// Adds a default welcome message to the current session.
    public func addWelcomeMessage() async throws {
        try await persistenceManager.addMessage(
            role: .assistant, 
            content: "Hi, how can I help you today?"
        )
    }
    
    /// Generates a descriptive title for the session if it's still named "New Conversation".
    public func generateTitleIfNeeded(messages: [Message]) async {
        guard let session = persistenceManager.currentSession,
              session.title == "New Conversation",
              messages.count >= 3 else {
            return
        }
        
        do {
            let title = try await llmService.generateTitle(for: messages)
            var updatedSession = session
            updatedSession.title = title
            try await persistenceManager.updateSession(updatedSession)
        } catch {
            logger.warning("Failed to auto-generate title: \(error.localizedDescription)")
        }
    }
}
