import MonadShared
import Foundation
import GRDB

// MARK: - Job Model

/// Represents a single job in the queue
public struct Job: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public let id: UUID
    public let sessionId: UUID
    public var parentId: UUID?
    public var title: String
    public var description: String?
    public var priority: Int
    public var agentId: String
    public var status: Status
    public let createdAt: Date
    public var updatedAt: Date
    public var logs: [String]
    public var retryCount: Int
    public var lastRetryAt: Date?
    public var nextRunAt: Date?

    public enum Status: String, Codable, Sendable, CaseIterable {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
        case cancelled
    }

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        parentId: UUID? = nil,
        title: String,
        description: String? = nil,
        priority: Int = 0,
        agentId: String = "default",
        status: Status = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        logs: [String] = [],
        retryCount: Int = 0,
        lastRetryAt: Date? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.parentId = parentId
        self.title = title
        self.description = description
        self.priority = priority
        self.agentId = agentId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.logs = logs
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
        self.nextRunAt = nextRunAt
    }
}



// MARK: - Persistence

extension Job {
    public static let databaseTableName = "job"
}

// MARK: - Formatting

extension Job {
    /// Format job for display
    public var formatted: String {
        let statusIcon: String
        switch status {
        case .pending: statusIcon = "○"
        case .inProgress: statusIcon = "◐"
        case .completed: statusIcon = "●"
        case .failed: statusIcon = "⊗"
        case .cancelled: statusIcon = "✕"
        }

        let priorityLabel = priority != 0 ? " [P\(priority)]" : ""
        let idShort = id.uuidString.prefix(8)

        var result = "\(statusIcon) [\(idShort)] \(title)\(priorityLabel)"
        if let desc = description, !desc.isEmpty {
            result += "\n   \(desc)"
        }
        return result
    }
}
