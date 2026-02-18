import Foundation
import MonadShared

public enum MemorySavePolicy: Sendable {
    case immediate
    case deferred
    case preventSimilar(threshold: Double)
}

public enum JobEvent: Sendable {
    case jobAdded(Job)
    case jobUpdated(Job)
    case jobDeleted(UUID)
}
