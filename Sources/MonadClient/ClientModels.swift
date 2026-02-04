import Foundation
import MonadCore

// MARK: - Type Aliases from MonadCore

// Session Models
public typealias Session = SessionResponse

// Chat Models
public typealias ChatRequest = MonadCore.ChatRequest
public typealias ChatResponse = MonadCore.ChatResponse

// Memory Models
public typealias Memory = MonadCore.Memory
public typealias MemorySearchRequest = MonadCore.MemorySearchRequest

// Note Models
public typealias Note = MonadCore.Note
public typealias CreateNoteRequest = MonadCore.CreateNoteRequest
public typealias UpdateNoteRequest = MonadCore.UpdateNoteRequest

// Tool Models
public typealias Tool = MonadCore.ToolInfo

// Message Models
public typealias Message = MonadCore.Message
public typealias MessageRole = MonadCore.Message.MessageRole

// MARK: - Client-Specific Models

/// A delta from a streaming chat response
public struct ChatDelta: Sendable {
    public let content: String?
    public let isDone: Bool

    public init(content: String? = nil, isDone: Bool = false) {
        self.content = content
        self.isDone = isDone
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