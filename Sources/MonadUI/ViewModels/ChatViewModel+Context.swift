import Foundation
import MonadCore

extension ChatViewModel {
    // MARK: - Active Context Management
    
    public func toggleMemoryPin(id: UUID) {
        if let index = activeMemories.firstIndex(where: { $0.id == id }) {
            activeMemories[index].isPinned.toggle()
        }
    }
    
    public func removeActiveMemory(id: UUID) {
        activeMemories.removeAll { $0.id == id }
    }
    
    internal func updateActiveMemories(with newMemories: [Memory]) {
        for memory in newMemories {
            if let index = activeMemories.firstIndex(where: { $0.id == memory.id }) {
                // Already active, just update access time
                activeMemories[index].lastAccessed = Date()
            } else {
                // Add new active memory
                activeMemories.append(ActiveMemory(memory: memory))
            }
        }
        
        // Prune if we have too many
        // We allow some buffer (e.g. 2x limit) but eventually we should remove oldest unpinned ones
        let limit = llmService.configuration.memoryContextLimit
        let maxBuffer = limit * 2
        
        let unpinnedCount = activeMemories.filter { !$0.isPinned }.count
        if unpinnedCount > maxBuffer {
            // Find unpinned ones, sort by oldest access
            let unpinnedIndices = activeMemories.enumerated()
                .filter { !$0.element.isPinned }
                .sorted { (a, b) -> Bool in
                    a.element.lastAccessed < b.element.lastAccessed
                }
                .map { $0.offset }
            
            // Remove enough to get back to limit
            let toRemove = unpinnedCount - limit
            let indicesToRemove = Set(unpinnedIndices.prefix(toRemove))
            
            activeMemories = activeMemories.enumerated()
                .filter { !indicesToRemove.contains($0.offset) }
                .map { $0.element }
            
            logger.debug("Pruned \(toRemove) active memories. Current count: \(self.activeMemories.count)")
        }
    }
}
