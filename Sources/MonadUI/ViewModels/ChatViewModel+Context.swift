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
    }
}
