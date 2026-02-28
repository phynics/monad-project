import Foundation
import MonadCore
import MonadShared

// MARK: - Type Aliases from MonadCore

// Session Models
public typealias Session = MonadShared.SessionResponse

// Chat Models
public typealias ChatRequest = MonadShared.ChatRequest
public typealias ChatResponse = MonadShared.ChatResponse

// Status Models
public typealias StatusResponse = MonadShared.StatusResponse
public typealias ComponentStatus = MonadShared.ComponentStatus
public typealias HealthStatus = MonadCore.HealthStatus

// Memory Models
public typealias Memory = MonadCore.Memory
public typealias MemorySearchRequest = MonadShared.MemorySearchRequest

// Tool Models
public typealias Tool = MonadShared.ToolInfo

// Message Models
public typealias Message = MonadCore.Message
public typealias MessageRole = MonadCore.Message.MessageRole

// Job Models
public typealias Job = MonadCore.Job
public typealias AddJobRequest = MonadCore.AddJobRequest

// MARK: - Client-Specific Models

/// A delta from a streaming chat response
public typealias ChatDelta = MonadShared.ChatDelta

/// A delta for a tool call in a streaming response
public typealias ToolCallDelta = MonadCore.ToolCallDelta

/// Metadata about the context used for a chat response
public typealias ChatMetadata = MonadCore.ChatMetadata

// MARK: - Client API Models
public typealias ClientIdentity = MonadShared.ClientIdentity
public typealias WorkspaceReference = MonadCore.WorkspaceReference
public typealias WorkspaceURI = MonadCore.WorkspaceURI
public typealias WorkspaceTrustLevel = MonadCore.WorkspaceTrustLevel
public typealias ToolReference = MonadCore.ToolReference
public typealias WorkspaceToolDefinition = MonadCore.WorkspaceToolDefinition
public typealias AnyCodable = MonadCore.AnyCodable

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
