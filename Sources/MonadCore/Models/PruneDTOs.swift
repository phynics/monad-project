import Foundation

public struct PruneQueryRequest: Codable {
    public let query: String
    public let dryRun: Bool?

    public init(query: String, dryRun: Bool? = false) {
        self.query = query
        self.dryRun = dryRun
    }
}

public struct PruneSessionRequest: Codable {
    public let days: Int
    public let excludedSessionIds: [UUID]?
    public let dryRun: Bool?

    public init(days: Int, excludedSessionIds: [UUID]? = nil, dryRun: Bool? = false) {
        self.days = days
        self.excludedSessionIds = excludedSessionIds
        self.dryRun = dryRun
    }
}

public struct PruneMessagesRequest: Codable {
    public let days: Int
    public let dryRun: Bool?

    public init(days: Int, dryRun: Bool? = false) {
        self.days = days
        self.dryRun = dryRun
    }
}

public struct PruneResponse: Codable {
    public let count: Int
    public let dryRun: Bool

    public init(count: Int, dryRun: Bool = false) {
        self.count = count
        self.dryRun = dryRun
    }
}
