import MonadCore
import OSLog

extension ChatViewModel {
    public func compressContext(scope: CompressionScope = .topic) async {
        Logger.chat.info("Attempting context compression (scope: \(scope))...")
        do {
            let compressed = try await contextCompressor.compress(messages: messages, scope: scope)

            // If the compressed array is different (shorter) than original, update persistence
            if compressed.count < messages.count
                || (scope == .broad && compressed.contains(where: { $0.summaryType == .broad }))
            {
                Logger.chat.notice("Compression successful. Replacing \(self.messages.count) messages with \(compressed.count).")
                try await persistenceManager.replaceMessages(with: compressed)
                messages = persistenceManager.uiMessages
            } else {
                Logger.chat.debug("Compression yielded no reduction.")
            }
        } catch {
            Logger.chat.error("Context compression failed: \(error.localizedDescription)")
        }
    }

    public func triggerMemoryVacuum() async {
        do {
            let count = try await persistenceManager.vacuumMemories()
            Logger.chat.info("Memory vacuum pruned \(count) memories.")
        } catch {
            Logger.chat.error("Memory vacuum failed: \(error.localizedDescription)")
        }
    }
}
