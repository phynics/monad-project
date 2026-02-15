import Dependencies
import Foundation

// MARK: - MonadEngine Integration

extension DependencyValues {
    /// Helper to inject all core dependencies from a MonadEngine instance
    public mutating func withEngine(_ engine: MonadEngine) {
        self.persistenceService = engine.persistenceService
        self.llmService = engine.llmService
        self.embeddingService = engine.embeddingService
        self.vectorStore = engine.vectorStore
        self.agentRegistry = engine.agentRegistry
        self.sessionManager = engine.sessionManager
        self.toolRouter = engine.toolRouter
        self.chatOrchestrator = engine.chatOrchestrator
    }
}