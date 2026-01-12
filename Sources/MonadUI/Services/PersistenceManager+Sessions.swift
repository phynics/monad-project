import Foundation
import MonadCore

extension PersistenceManager {
    public func createNewSession(title: String = "New Conversation") async throws {
        logger.info("Creating new session: \(title)")
        var session = ConversationSession(title: title)
        session.isArchived = false
        try await persistence.saveSession(session)
        currentSession = session
        currentMessages = []
    }

    public func fetchLatestSession() async throws -> ConversationSession? {
        logger.debug("Fetching latest session")
        let all = try await persistence.fetchAllSessions(includeArchived: true)
        return all.first
    }

    public func loadSession(id: UUID) async throws {
        logger.info("Loading session: \(id.uuidString)")
        guard let session = try await persistence.fetchSession(id: id) else {
            logger.error("Session not found: \(id.uuidString)")
            throw PersistenceError.sessionNotFound
        }
        currentSession = session
        let flatMessages = try await persistence.fetchMessages(for: id).map { [weak self] dbMsg -> Message in
            var msg = dbMsg.toMessage()
            if let self = self, let info = self.debugInfoCache[msg.id] {
                msg.debugInfo = info
            }
            return msg
        }
        currentMessages = .constructForest(from: flatMessages)
    }

    public func updateSession(_ session: ConversationSession) async throws {
        logger.debug("Updating session: \(session.id.uuidString)")
        try await persistence.saveSession(session)
        if currentSession?.id == session.id {
            currentSession = session
        }
    }
    
    public func updateWorkingDirectory(_ path: String?) async throws {
        guard var session = currentSession else { return }
        session.workingDirectory = path
        try await persistence.saveSession(session)
        currentSession = session
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

        currentSession = nil
        currentMessages = []

        await loadActiveSessions()
        await loadArchivedSessions()
    }

    public func unarchiveSession(_ session: ConversationSession) async throws {
        logger.info("Unarchiving session: \(session.id)")
        var updated = session
        updated.isArchived = false
        updated.updatedAt = Date()
        try await persistence.saveSession(updated)
        
        await loadActiveSessions()
        await loadArchivedSessions()
        
        currentSession = updated
        let flatMessages = try await persistence.fetchMessages(for: session.id).map { $0.toMessage() }
        currentMessages = .constructForest(from: flatMessages)
    }

    public func deleteSession(id: UUID) async throws {
        logger.warning("Deleting session: \(id.uuidString)")
        try await persistence.deleteSession(id: id)
        if currentSession?.id == id {
            currentSession = nil
            currentMessages = []
        }
    }

    public func loadActiveSessions() async {
        do {
            activeSessions = try await persistence.fetchAllSessions(includeArchived: false)
            errorMessage = nil
        } catch {
            logger.error("Failed to load active sessions: \(error.localizedDescription)")
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
        }
    }

    public func loadArchivedSessions() async {
        do {
            let allSessions = try await persistence.fetchAllSessions(includeArchived: true)
            archivedSessions = allSessions.filter { $0.isArchived }
            errorMessage = nil
        } catch {
            logger.error("Failed to load archived sessions: \(error.localizedDescription)")
            errorMessage = "Failed to load archived sessions: \(error.localizedDescription)"
        }
    }

    public func searchArchivedSessions(query: String) async throws -> [ConversationSession] {
        try await persistence.searchArchivedSessions(query: query)
    }
}
