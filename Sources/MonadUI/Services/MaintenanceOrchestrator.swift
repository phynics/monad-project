import Foundation
import MonadCore
import OSLog

/// Orchestrates maintenance tasks like compression and vacuuming.
@MainActor
public final class MaintenanceOrchestrator {
    private let contextCompressor: ContextCompressor
    private let persistenceManager: PersistenceManager
    private let logger = Logger(subsystem: "com.monad.ui", category: "MaintenanceOrchestrator")
    
    public init(
        contextCompressor: ContextCompressor,
        persistenceManager: PersistenceManager
    ) {
        self.contextCompressor = contextCompressor
        self.persistenceManager = persistenceManager
    }
    
    /// Compresses the conversation context.
    /// Returns true if compression resulted in a shorter message history.
    public func compressContext(
        messages: [Message],
        scope: CompressionScope = .topic
    ) async throws -> [Message]? {
        logger.info("Attempting context compression (scope: \(scope))...")
        
        let compressed = try await contextCompressor.compress(messages: messages, scope: scope)
        
        if compressed.count < messages.count
            || (scope == .broad && compressed.contains(where: { $0.summaryType == .broad }))
        {
            logger.notice("Compression successful. Reduced from \(messages.count) to \(compressed.count) messages.")
            try await persistenceManager.replaceMessages(with: compressed)
            return compressed
        } else {
            logger.debug("Compression yielded no reduction.")
            return nil
        }
    }
    
    /// Triggers memory vacuuming to prune redundant memories.
    public func triggerMemoryVacuum() async throws -> Int {
        let count = try await persistenceManager.vacuumMemories()
        logger.info("Memory vacuum pruned \(count) memories.")
        return count
    }
}
