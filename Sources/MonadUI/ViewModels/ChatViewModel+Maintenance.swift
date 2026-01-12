import MonadCore
import OSLog

extension ChatViewModel {
    public func compressContext(scope: CompressionScope = .topic) async {
        do {
            if try await maintenanceOrchestrator.compressContext(messages: messages, scope: scope) != nil {
                messages = persistenceManager.uiMessages
            }
        } catch {
            Logger.chat.error("Context compression failed: \(error.localizedDescription)")
        }
    }

    public func triggerMemoryVacuum() async {
        do {
            _ = try await maintenanceOrchestrator.triggerMemoryVacuum()
        } catch {
            Logger.chat.error("Memory vacuum failed: \(error.localizedDescription)")
        }
    }
}
