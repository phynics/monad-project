import Foundation

public struct PruneQueryRequest: Codable {
    public let query: String

    public init(query: String) {
        self.query = query
    }
}

public struct PruneSessionRequest: Codable {
    public let days: Int
    public let excludedSessionIds: [UUID]?

    public init(days: Int, excludedSessionIds: [UUID]? = nil) {
        self.days = days
        self.excludedSessionIds = excludedSessionIds
    }
}

public struct PruneMessagesRequest: Codable {
    public let days: Int

    public init(days: Int) {
        self.days = days
    }
}

public struct PruneResponse: Codable {
    public let count: Int

    public init(count: Int) {
        self.count = count
    }
}
