import Foundation
import OSLog
import MonadCore

extension ChatViewModel {
    // MARK: - Startup Logic
    
    internal func checkStartupState() async {
        do {
            if let latest = try await persistenceManager.fetchLatestSession() {
                try await persistenceManager.loadSession(id: latest.id)
                messages = persistenceManager.uiMessages
            } else {
                // No sessions, start new
                try await persistenceManager.createNewSession()
            }
        } catch {
            Logger.chat.error("Failed to check startup state: \(error.localizedDescription)")
            // Fallback to new session
            try? await persistenceManager.createNewSession()
        }
    }
    
    public func startNewSession(deleteOld: Bool = false) {
        Task {
            do {
                if deleteOld, let session = persistenceManager.currentSession {
                    try await persistenceManager.deleteSession(id: session.id)
                }
                // Create new persistent session
                try await persistenceManager.createNewSession()
                messages = []
                activeMemories = [] // Clear active memories on new session
            } catch {
                errorMessage = "Failed to start new session: \(error.localizedDescription)"
            }
        }
    }

    public func archiveConversation(confirmationDismiss: @escaping () -> Void) {
        // "Archive" now effectively means "Start New Conversation"
        // We trigger the archiver in the background for memory indexing/optimization
        // but we don't wait for it to clear the UI.
        let messagesToArchive = messages
        Task {
            try? await conversationArchiver.archive(messages: messagesToArchive)
        }
        
        startNewSession(deleteOld: false)
        confirmationDismiss()
    }

    public func clearConversation() {
        Logger.chat.debug("Clearing conversation")
        startNewSession(deleteOld: true)
    }

    internal func generateTitleIfNeeded() {
        // Generate title after 3 messages (usually User + Assistant + User)
        // Check if we already have a custom title (not "New Conversation")
        guard let session = persistenceManager.currentSession,
              session.title == "New Conversation",
              messages.count >= 3 else {
            return
        }
        
        Task {
            do {
                let title = try await llmService.generateTitle(for: messages)
                var updatedSession = session
                updatedSession.title = title
                try await persistenceManager.updateSession(updatedSession)
            } catch {
                Logger.chat.warning("Failed to auto-generate title: \(error.localizedDescription)")
            }
        }
    }
}
