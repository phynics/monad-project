import Foundation
import MonadCore

public struct ActiveMemory: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let memory: Memory
    public var isPinned: Bool
    public var lastAccessed: Date
    
    public init(memory: Memory, isPinned: Bool = false, lastAccessed: Date = Date()) {
        self.id = memory.id
        self.memory = memory
        self.isPinned = isPinned
        self.lastAccessed = lastAccessed
    }
}
