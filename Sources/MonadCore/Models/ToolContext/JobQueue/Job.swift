import Foundation

// MARK: - Job Model

/// Represents a single job in the queue
public struct Job: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var description: String?
    public var priority: Int
    public var status: Status
    public let createdAt: Date
    public var updatedAt: Date

    public enum Status: String, Codable, Sendable, CaseIterable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled
    }

    public init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        priority: Int = 0,
        status: Status = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
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
