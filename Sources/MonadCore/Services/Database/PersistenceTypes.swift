import MonadShared
import Foundation

public enum MemorySavePolicy: Sendable {
    case immediate
    case deferred
    case preventSimilar(threshold: Double)
}

public enum BackgroundJobEvent: Sendable {
    case jobAdded(BackgroundJob)
    case jobUpdated(BackgroundJob)
    case jobDeleted(UUID)
}
