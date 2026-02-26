import Foundation
import MonadCore

public struct ChatRequest: Codable, Sendable {
    public let message: String
    public let toolOutputs: [ToolOutputSubmission]?
    public let clientId: UUID?

    public init(message: String, toolOutputs: [ToolOutputSubmission]? = nil, clientId: UUID? = nil) {
        self.message = message
        self.toolOutputs = toolOutputs
        self.clientId = clientId
    }
}

public struct ChatResponse: Codable, Sendable {
    public let response: String

    public init(response: String) {
        self.response = response
    }
}

/// The type of discrete lifecycle event in the chat stream
public enum StreamEventType: String, Sendable, Codable {
    case generationContext
    case delta
    case thought
    case thoughtCompleted
    case toolCall
    case toolCallError
    case toolExecution
    case generationCompleted
    case generationCancelled
    case streamCompleted
    case error
}

/// A delta or lifecycle event from a streaming chat response
public struct ChatDelta: Sendable, Codable {
    public let type: StreamEventType
    
    // Payloads
    public let content: String?
    public let thought: String?
    public let toolCalls: [ToolCallDelta]?
    public let toolExecution: ToolExecutionDelta?
    public let toolCallError: ToolCallErrorDelta?
    public let metadata: ChatMetadata?
    public let responseMetadata: APIMetadataDelta?
    public let error: String?

    public init(
        type: StreamEventType,
        content: String? = nil,
        thought: String? = nil,
        toolCalls: [ToolCallDelta]? = nil,
        toolExecution: ToolExecutionDelta? = nil,
        toolCallError: ToolCallErrorDelta? = nil,
        metadata: ChatMetadata? = nil,
        responseMetadata: APIMetadataDelta? = nil,
        error: String? = nil
    ) {
        self.type = type
        self.content = content
        self.thought = thought
        self.toolCalls = toolCalls
        self.toolExecution = toolExecution
        self.toolCallError = toolCallError
        self.metadata = metadata
        self.responseMetadata = responseMetadata
        self.error = error
    }
}

public struct ToolCallErrorDelta: Sendable, Codable {
    public let toolCallId: String
    public let name: String
    public let error: String

    public init(toolCallId: String, name: String, error: String) {
        self.toolCallId = toolCallId
        self.name = name
        self.error = error
    }
}

public struct APIMetadataDelta: Equatable, Sendable, Codable {
    public var model: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var finishReason: String?
    public var systemFingerprint: String?
    public var duration: TimeInterval?
    public var tokensPerSecond: Double?
    public var debugSnapshotData: Data?

    public init(
        model: String? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil,
        totalTokens: Int? = nil, finishReason: String? = nil, systemFingerprint: String? = nil,
        duration: TimeInterval? = nil, tokensPerSecond: Double? = nil,
        debugSnapshotData: Data? = nil
    ) {
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.finishReason = finishReason
        self.systemFingerprint = systemFingerprint
        self.duration = duration
        self.tokensPerSecond = tokensPerSecond
        self.debugSnapshotData = debugSnapshotData
    }
}

public struct ToolExecutionDelta: Sendable, Codable {
    public let toolCallId: String
    public let status: String // "attempting", "success", "failure"
    public let name: String?
    public let target: String?
    public let result: String?

    public init(toolCallId: String, status: String, name: String? = nil, target: String? = nil, result: String? = nil) {
        self.toolCallId = toolCallId
        self.status = status
        self.name = name
        self.target = target
        self.result = result
    }
}
