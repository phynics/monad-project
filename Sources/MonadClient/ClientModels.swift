import ErrorKit
import Foundation
import PKShared
import MonadShared

// MARK: - Type Aliases from Shared Modules

/// Timeline Models
public typealias Timeline = MonadShared.TimelineResponse

// Chat Models
public typealias ChatRequest = MonadShared.ChatRequest
public typealias ChatResponse = MonadShared.ChatResponse

// Status Models
public typealias StatusResponse = MonadShared.StatusResponse
public typealias ComponentStatus = MonadShared.ComponentStatus
public typealias HealthStatus = PKShared.HealthStatus

// Memory Models
public typealias Memory = PKShared.Memory
public typealias MemorySearchRequest = MonadShared.MemorySearchRequest

/// Tool Models
public typealias Tool = MonadShared.ToolInfo

/// AgentTemplate Models
public typealias AgentTemplate = PKShared.AgentTemplate

// Message Models
public typealias Message = PKShared.Message
public typealias MessageRole = PKShared.Message.MessageRole

// MARK: - Client-Specific Models

/// A delta for a tool call in a streaming response
public typealias ToolCallDelta = PKShared.ToolCallDelta

/// Metadata about the context used for a chat response
public typealias ChatMetadata = PKShared.ChatMetadata

// MARK: - Client API Models

public typealias RequestOriginIdentity = PKShared.RequestOriginIdentity
public typealias RequestOriginRegistrationRequest = MonadShared.RequestOriginRegistrationRequest
public typealias RequestOriginRegistrationResponse = MonadShared.RequestOriginRegistrationResponse

public typealias ClientIdentity = PKShared.RequestOriginIdentity
public typealias ClientRegistrationRequest = MonadShared.RequestOriginRegistrationRequest
public typealias ClientRegistrationResponse = MonadShared.RequestOriginRegistrationResponse
public typealias WorkspaceReference = PKShared.WorkspaceReference
public typealias WorkspaceURI = PKShared.WorkspaceURI
public typealias WorkspaceTrustLevel = PKShared.WorkspaceTrustLevel
public typealias ToolReference = PKShared.ToolReference
public typealias WorkspaceToolDefinition = PKShared.WorkspaceToolDefinition
public typealias AnyCodable = PKShared.AnyCodable

// MARK: - Error Models

/// Errors that can occur when communicating with the server
public enum MonadClientError: PKError {
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case serverNotReachable
    case unauthorized
    case notFound
    case unknown(String)

    public var errorDomain: String { PKErrorDomain.client }

    public var errorCode: Int {
        switch self {
        case .invalidURL: return 1001
        case .networkError: return 1002
        case .httpError(let statusCode, _): return 2000 + statusCode
        case .decodingError: return 1003
        case .serverNotReachable: return 1004
        case .unauthorized: return 1005
        case .notFound: return 1006
        case .unknown: return 1007
        }
    }

    public var userFriendlyMessage: String {
        switch self {
        case .invalidURL:
            return "The server URL is configured incorrectly."
        case .networkError:
            return "Could not connect to the server. Please check your internet connection."
        case let .httpError(statusCode, _):
            if statusCode == 401 || statusCode == 403 {
                return "Your API key is invalid or has expired."
            } else if statusCode >= 500 {
                return "The Monad server is experiencing an internal issue."
            }
            return "The server returned an unexpected error (HTTP \(statusCode))."
        case .decodingError:
            return "The server returned data in an unexpected format."
        case .serverNotReachable:
            return "The Monad server is not reachable. Please ensure it is running."
        case .unauthorized:
            return "You are not authorized to perform this action. Please check your API key."
        case .notFound:
            return "The requested resource was not found on the server."
        case let .unknown(message):
            return message
        }
    }
}
