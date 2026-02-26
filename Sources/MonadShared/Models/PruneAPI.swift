import Foundation
import MonadCore

public struct PruneMemoriesRequest: Codable, Sendable {
    public let query: String?
    public let days: Int?
    public let dryRun: Bool

    public init(query: String? = nil, days: Int? = nil, dryRun: Bool = false) {
        self.query = query
        self.days = days
        self.dryRun = dryRun
    }
}

public struct PruneSessionRequest: Codable, Sendable {
    public let days: Int
    public let excludedSessionIds: [UUID]
    public let dryRun: Bool

    public init(days: Int, excludedSessionIds: [UUID] = [], dryRun: Bool = false) {
        self.days = days
        self.excludedSessionIds = excludedSessionIds
        self.dryRun = dryRun
    }
}

public struct PruneMessagesRequest: Codable, Sendable {
    public let days: Int
    public let dryRun: Bool

    public init(days: Int, dryRun: Bool = false) {
        self.days = days
        self.dryRun = dryRun
    }
}

public struct PruneResponse: Codable, Sendable {
    public let count: Int
    public let dryRun: Bool

    public init(count: Int, dryRun: Bool) {
        self.count = count
        self.dryRun = dryRun
    }
}
