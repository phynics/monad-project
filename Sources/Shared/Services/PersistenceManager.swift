import Foundation
import OSLog
import Observation
import SwiftUI

/// Main actor wrapper for PersistenceService that works with SwiftUI
/// Main actor wrapper for PersistenceService that works with SwiftUI
@MainActor
@Observable
public final class PersistenceManager {
    public private(set) var currentSession: ConversationSession?
    public private(set) var currentMessages: [ConversationMessage] = []
    public private(set) var archivedSessions: [ConversationSession] = []
    public private(set) var activeSessions: [ConversationSession] = []

    private let persistence: PersistenceService
    private let logger = Logger.database

    public init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    // MARK: - Session Management

    public func createNewSession(title: String = "New Conversation") async throws {
        logger.info("Creating new session: \(title)")
        let session = ConversationSession(title: title)
        try await persistence.saveSession(session)
        currentSession = session
        currentMessages = []
    }

    public func loadSession(id: UUID) async throws {
        logger.info("Loading session: \(id.uuidString)")
        guard let session = try await persistence.fetchSession(id: id) else {
            logger.error("Session not found: \(id.uuidString)")
            throw PersistenceError.sessionNotFound
        }
        currentSession = session
        currentMessages = try await persistence.fetchMessages(for: id)
    }

    public func updateSession(_ session: ConversationSession) async throws {
        logger.debug("Updating session: \(session.id.uuidString)")
        try await persistence.saveSession(session)

        // Update local state if it's the current session
        if currentSession?.id == session.id {
            currentSession = session
        }
    }

    public func archiveCurrentSession() async throws {
        guard var session = currentSession else {
            logger.warning("Attempted to archive session but none is active")
            throw PersistenceError.noActiveSession
        }

        logger.info("Archiving current session: \(session.id.uuidString)")
        session.isArchived = true
        session.updatedAt = Date()
        try await persistence.saveSession(session)

        // Clear current session
        currentSession = nil
        currentMessages = []

        // Reload lists
        await loadActiveSessions()
        await loadArchivedSessions()
    }

    public func deleteSession(id: UUID) async throws {
        logger.warning("Deleting session: \(id.uuidString)")
        try await persistence.deleteSession(id: id)

        // Clear if current
        if currentSession?.id == id {
            currentSession = nil
            currentMessages = []
        }
    }

    // MARK: - Message Management

    public func addMessage(role: ConversationMessage.MessageRole, content: String) async throws {
        guard let session = currentSession else {
            logger.error("Attempted to add message but no active session")
            throw PersistenceError.noActiveSession
        }

        let message = ConversationMessage(
            sessionId: session.id,
            role: role,
            content: content
        )

        logger.debug("Saving message for session \(session.id.uuidString)")
        try await persistence.saveMessage(message)

        // Update local state
        currentMessages.append(message)

        // Update session timestamp
        var updatedSession = session
        updatedSession.updatedAt = Date()
        try await persistence.saveSession(updatedSession)
        currentSession = updatedSession
    }

    // MARK: - Memory Management

    public func saveMemory(_ memory: Memory) async throws {
        logger.info("Saving memory: \(memory.title)")
        try await persistence.saveMemory(memory)
    }

    public func fetchMemory(id: UUID) async throws -> Memory? {
        try await persistence.fetchMemory(id: id)
    }

    public func fetchAllMemories() async throws -> [Memory] {
        try await persistence.fetchAllMemories()
    }

    public func searchMemories(query: String) async throws -> [Memory] {
        logger.info("Searching memories for: \(query)")
        return try await persistence.searchMemories(query: query)
    }

    public func deleteMemory(id: UUID) async throws {
        logger.warning("Deleting memory: \(id.uuidString)")
        try await persistence.deleteMemory(id: id)
    }

    // MARK: - List Management

    public func loadActiveSessions() async {
        do {
            activeSessions = try await persistence.fetchAllSessions(includeArchived: false)
            logger.debug("Loaded \(self.activeSessions.count) active sessions")
        } catch {
            logger.error("Failed to load active sessions: \(error.localizedDescription)")
        }
    }

    public func loadArchivedSessions() async {
        do {
            let allSessions = try await persistence.fetchAllSessions(includeArchived: true)
            archivedSessions = allSessions.filter { $0.isArchived }
            logger.debug("Loaded \(self.archivedSessions.count) archived sessions")
        } catch {
            logger.error("Failed to load archived sessions: \(error.localizedDescription)")
        }
    }

    public func searchArchivedSessions(query: String) async throws -> [ConversationSession] {
        logger.info("Searching archived sessions for: \(query)")
        return try await persistence.searchArchivedSessions(query: query)
    }

    // MARK: - Memory Management

    public func saveMemory(_ memory: Memory) async throws {
        logger.info("Saving memory: \(memory.title)")
        try await persistence.saveMemory(memory)
    }

    public func fetchMemory(id: UUID) async throws -> Memory? {
        try await persistence.fetchMemory(id: id)
    }

    public func fetchAllMemories() async throws -> [Memory] {
        try await persistence.fetchAllMemories()
    }

    public func searchMemories(query: String) async throws -> [Memory] {
        logger.info("Searching memories for: \(query)")
        return try await persistence.searchMemories(query: query)
    }

    public func deleteMemory(id: UUID) async throws {
        logger.warning("Deleting memory: \(id.uuidString)")
        try await persistence.deleteMemory(id: id)
    }

    // MARK: - Notes Management

    public func saveNote(_ note: Note) async throws {
        logger.info("Saving note: \(note.name)")
        try await persistence.saveNote(note)
    }

    public func fetchNote(id: UUID) async throws -> Note? {
        try await persistence.fetchNote(id: id)
    }

    public func fetchAllNotes() async throws -> [Note] {
        try await persistence.fetchAllNotes()
    }

    public func fetchAlwaysAppendNotes() async throws -> [Note] {
        try await persistence.fetchAlwaysAppendNotes()
    }

    public func searchNotes(query: String) async throws -> [Note] {
        logger.info("Searching notes for: \(query)")
        return try await persistence.searchNotes(query: query)
    }

    public func deleteNote(id: UUID) async throws {
        logger.warning("Deleting note: \(id.uuidString)")
        try await persistence.deleteNote(id: id)
    }

    public func getContextNotes(alwaysAppend: Bool = false) async throws -> String {
        try await persistence.getContextNotes(alwaysAppend: alwaysAppend)
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
