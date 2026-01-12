import Foundation
import MonadCore
import OSLog

extension ChatViewModel {
    // MARK: - Startup Logic

    public func checkStartupState() async {
        // Load active sessions
        await persistenceManager.loadActiveSessions()
        await persistenceManager.loadArchivedSessions()
        
        // Refresh jobs
        await refreshJobs()
    }
    
    /// Handle configuration updates from settings
    public func applyConfiguration(_ config: LLMConfiguration) async throws {
        // 1. Update coordinator (switches between Local/Remote)
        try await coordinator.update(with: config)
        
        // 2. Sync persistence manager with active persistence service
        persistenceManager.persistence = coordinator.activePersistenceService
        
        // 3. Update job queue context
        self.jobQueueContext.updatePersistence(coordinator.activePersistenceService)
        
        // 4. Refresh UI state from new source of truth
        await checkStartupState()
    }

    public func startNewSession(deleteOld: Bool = false) {
        Task {
            do {
                try await sessionOrchestrator.startNewSession(deleteOld: deleteOld)

                // Invalidate tools to reset working directory
                invalidateToolInfrastructure()

                messages = persistenceManager.uiMessages
                activeMemories = []  // Clear active memories on new session
                await addWelcomeMessage()
            } catch {
                errorMessage = "Failed to start new session: \(error.localizedDescription)"
            }
        }
    }

    private func addWelcomeMessage() async {
        do {
            try await sessionOrchestrator.addWelcomeMessage()
            messages = persistenceManager.uiMessages
        } catch {
            Logger.chat.error("Failed to add welcome message: \(error.localizedDescription)")
        }
    }

    public func archiveConversation(confirmationDismiss: @escaping () -> Void) {
        // "Archive" now effectively means "Start New Conversation"
        // We trigger the archiver in the background for memory indexing/optimization
        // but we don't wait for it to clear the UI.
        let messagesToArchive = messages
        let sessionId = persistenceManager.currentSession?.id

        Task {
            try? await conversationArchiver.archive(
                messages: messagesToArchive, sessionId: sessionId)
        }

        startNewSession(deleteOld: false)
        confirmationDismiss()
    }

    public func clearConversation() {
        Logger.chat.debug("Clearing conversation")
        startNewSession(deleteOld: true)
    }

    internal func generateTitleIfNeeded() {
        Task {
            await sessionOrchestrator.generateTitleIfNeeded(messages: messages)
        }
    }
}