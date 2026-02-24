import Foundation
import MonadCore

// MARK: - Type Aliases from MonadCore

// Session Models
public typealias Session = SessionResponse

// Chat Models
public typealias ChatRequest = ChatRequest
public typealias ChatResponse = ChatResponse

// Status Models
public typealias StatusResponse = StatusResponse
public typealias ComponentStatus = ComponentStatus
public typealias HealthStatus = HealthStatus

// Memory Models
public typealias Memory = MonadCore.Memory
public typealias MemorySearchRequest = MemorySearchRequest

// Tool Models
public typealias Tool = ToolInfo

// Message Models
public typealias Message = MonadCore.Message
public typealias MessageRole = MonadCore.Message.MessageRole

// Job Models
public typealias Job = MonadCore.Job
public typealias AddJobRequest = AddJobRequest

// MARK: - Client-Specific Models

/// A delta from a streaming chat response
public typealias ChatDelta = ChatDelta

/// A delta for a tool call in a streaming response
public typealias ToolCallDelta = ToolCallDelta

/// Metadata about the context used for a chat response
public typealias ChatMetadata = ChatMetadata

// MARK: - Client API Models
public typealias ClientIdentity = ClientIdentity
public typealias WorkspaceReference = WorkspaceReference
public typealias WorkspaceURI = WorkspaceURI
public typealias WorkspaceTrustLevel = WorkspaceTrustLevel
public typealias ToolReference = ToolReference
public typealias WorkspaceToolDefinition = WorkspaceToolDefinition
public typealias AnyCodable = AnyCodable

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
