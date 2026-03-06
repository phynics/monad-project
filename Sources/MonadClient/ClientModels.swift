import Foundation
import MonadShared

// MARK: - Type Aliases from MonadShared

/// Session Models
public typealias Session = MonadShared.SessionResponse

// Chat Models
public typealias ChatRequest = MonadShared.ChatRequest
public typealias ChatResponse = MonadShared.ChatResponse

// Status Models
public typealias StatusResponse = MonadShared.StatusResponse
public typealias ComponentStatus = MonadShared.ComponentStatus
public typealias HealthStatus = MonadShared.HealthStatus

// Memory Models
public typealias Memory = MonadShared.Memory
public typealias MemorySearchRequest = MonadShared.MemorySearchRequest

/// Tool Models
public typealias Tool = MonadShared.ToolInfo

/// Agent Models
public typealias Agent = MonadShared.Agent

// Message Models
public typealias Message = MonadShared.Message
public typealias MessageRole = MonadShared.Message.MessageRole

// Job Models
public typealias Job = MonadShared.Job
public typealias AddJobRequest = MonadShared.AddJobRequest

// MARK: - Client-Specific Models

/// A delta for a tool call in a streaming response
public typealias ToolCallDelta = MonadShared.ToolCallDelta

/// Metadata about the context used for a chat response
public typealias ChatMetadata = MonadShared.ChatMetadata

// MARK: - Client API Models

public typealias ClientIdentity = MonadShared.ClientIdentity
public typealias WorkspaceReference = MonadShared.WorkspaceReference
public typealias WorkspaceURI = MonadShared.WorkspaceURI
public typealias WorkspaceTrustLevel = MonadShared.WorkspaceTrustLevel
public typealias ToolReference = MonadShared.ToolReference
public typealias WorkspaceToolDefinition = MonadShared.WorkspaceToolDefinition
public typealias AnyCodable = MonadShared.AnyCodable

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
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case let .httpError(statusCode, message):
            return "HTTP \(statusCode): \(message ?? "Unknown error")"
        case let .decodingError(error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverNotReachable:
            return "Server is not reachable"
        case .unauthorized:
            return "Unauthorized - check your API key"
        case .notFound:
            return "Resource not found"
        case let .unknown(message):
            return message
        }
    }
}
