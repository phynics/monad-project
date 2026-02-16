import MonadShared
import Foundation

/// Request object for executing a tool remotely
public struct ToolExecutionRequest: Codable, Sendable {
    public let toolId: String
    public let parameters: [String: AnyCodable] // dynamic JSON
    
    public init(toolId: String, parameters: [String: Any]) {
        self.toolId = toolId
        self.parameters = parameters.mapValues { AnyCodable($0) }
    }
    
    public init(toolId: String, parameters: [String: AnyCodable]) {
        self.toolId = toolId
        self.parameters = parameters
    }
}

/// Response object from a tool execution
public struct ToolExecutionResponse: Codable, Sendable {
    public let status: String // "success" or "error"
    public let output: String
    public let error: String?
    
    public init(status: String, output: String, error: String? = nil) {
        self.status = status
        self.output = output
        self.error = error
    }
    
    public var isSuccess: Bool {
        return status == "success"
    }
}

/// Request to list files
public struct ListFilesRequest: Codable, Sendable {
    public let path: String
    
    public init(path: String) {
        self.path = path
    }
}

/// Request to read a file
public struct ReadFileRequest: Codable, Sendable {
    public let path: String
    
    public init(path: String) {
        self.path = path
    }
}

/// Request to write a file
public struct WriteFileRequest: Codable, Sendable {
    public let path: String
    public let content: String
    
    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}


/// Generic RPC Request Envelope
public struct RPCRequest: Codable, Sendable {
    public let id: String
    public let method: String
    public let params: AnyCodable?
    
    public init(id: String = UUID().uuidString, method: String, params: AnyCodable?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Generic RPC Response Envelope
public struct RPCResponse: Codable, Sendable {
    public let id: String
    public let result: AnyCodable?
    public let error: String?
    
    public init(id: String, result: AnyCodable?, error: String? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

/// Error type for RPC failures
public enum RPCError: Error, LocalizedError {
    case timeout
    case connectionLost
    case invalidResponse
    case remoteError(String)
    
    public var errorDescription: String? {
        switch self {
        case .timeout: return "RPC request timed out"
        case .connectionLost: return "Connection to client lost"
        case .invalidResponse: return "Received invalid response from client"
        case .remoteError(let msg): return "Remote error: \(msg)"
        }
    }
}


