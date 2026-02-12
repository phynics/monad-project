import Foundation

/// Request object for executing a tool remotely
public struct ToolExecutionRequest: Codable, Sendable {
    public let toolId: String
    public let parameters: [String: AnyCodable] // dynamic JSON
    
    public init(toolId: String, parameters: [String: Any]) {
        self.toolId = toolId
        self.parameters = parameters.mapValues { AnyCodable($0) }
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


