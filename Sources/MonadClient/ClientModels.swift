import Foundation

// MARK: - Session Models

/// A chat session
public struct Session: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let isArchived: Bool
    public let tags: [String]
    public let workingDirectory: String?
    public let primaryWorkspaceId: UUID?
    public let attachedWorkspaceIds: [UUID]

    public init(
        id: UUID,
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        tags: [String] = [],
        workingDirectory: String? = nil,
        primaryWorkspaceId: UUID? = nil,
        attachedWorkspaceIds: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.tags = tags
        self.workingDirectory = workingDirectory
        self.primaryWorkspaceId = primaryWorkspaceId
        self.attachedWorkspaceIds = attachedWorkspaceIds
    }

    /// All workspace IDs (primary + attached)
    public var allWorkspaces: [UUID] {
        var all: [UUID] = []
        if let primary = primaryWorkspaceId {
            all.append(primary)
        }
        all.append(contentsOf: attachedWorkspaceIds)
        return all
    }
}

// MARK: - Chat Models

/// Request to send a chat message
public struct ChatRequest: Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Response from a non-streaming chat request
public struct ChatResponse: Codable, Sendable {
    public let response: String

    public init(response: String) {
        self.response = response
    }
}

/// A delta from a streaming chat response
public struct ChatDelta: Sendable {
    public let content: String?
    public let isDone: Bool

    public init(content: String? = nil, isDone: Bool = false) {
        self.content = content
        self.isDone = isDone
    }
}

// MARK: - Message Models

/// Role of a message sender
public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}

/// A conversation message
public struct Message: Codable, Sendable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let role: MessageRole
    public let content: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(), sessionId: UUID, role: MessageRole, content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - Memory Models

/// A memory record
public struct Memory: Codable, Sendable, Identifiable {
    public let id: UUID
    public let content: String
    public let tags: [String]
    public let createdAt: Date

    public init(id: UUID = UUID(), content: String, tags: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
    }
}

/// Request to search memories
public struct MemorySearchRequest: Codable, Sendable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

// MARK: - Note Models

/// A note
public struct Note: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let content: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(), title: String, content: String, createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Request to create a note
public struct CreateNoteRequest: Codable, Sendable {
    public let title: String
    public let content: String

    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}

/// Request to update a note
public struct UpdateNoteRequest: Codable, Sendable {
    public let title: String?
    public let content: String?

    public init(title: String? = nil, content: String? = nil) {
        self.title = title
        self.content = content
    }
}

// MARK: - Tool Models

/// A tool definition
public struct Tool: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let isEnabled: Bool

    public init(id: String, name: String, description: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.isEnabled = isEnabled
    }
}

// MARK: - Error Models

/// Errors that can occur when communicating with the server
public enum MonadClientError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case serverNotReachable
    case unauthorized
    case notFound
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverNotReachable:
            return "Server is not reachable"
        case .unauthorized:
            return "Unauthorized - check your API key"
        case .notFound:
            return "Resource not found"
        case .unknown(let message):
            return message
        }
    }
}
