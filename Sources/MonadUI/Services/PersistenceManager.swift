import Foundation
import OSLog
import Observation
import SwiftUI
import MonadCore

/// Main actor wrapper for PersistenceService that works with SwiftUI
@MainActor
@Observable
public final class PersistenceManager {
    public internal(set) var currentSession: ConversationSession?
    public internal(set) var currentMessages: [MessageNode] = []
    public internal(set) var archivedSessions: [ConversationSession] = []
    public internal(set) var activeSessions: [ConversationSession] = []
    public var errorMessage: String?
    
    // In-memory cache for transient debug info
    internal var debugInfoCache: [UUID: MessageDebugInfo] = [:]

    public var uiMessages: [Message] {
        currentMessages.flattened()
    }

    public let persistence: PersistenceService
    internal let logger = Logger.database

    public init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    // MARK: - Database Reset

    public func resetDatabase() async throws {
        logger.warning("Resetting database to defaults")
        try await persistence.resetDatabase()

        // Clear in-memory state
        currentSession = nil
        currentMessages = []
        archivedSessions = []
        activeSessions = []
        debugInfoCache = [:]
    }
}

// MARK: - Errors

public enum PersistenceError: LocalizedError {
    case sessionNotFound
    case noActiveSession

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Conversation session not found"
        case .noActiveSession:
            return "No active conversation session"
        }
    }
}
