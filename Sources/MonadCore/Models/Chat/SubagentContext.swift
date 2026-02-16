import MonadShared
import Foundation

/// Context information for a subagent execution
public struct SubagentContext: Equatable, Sendable, Codable {
    public let prompt: String
    public let documents: [String]  // Paths
    public let rawResponse: String?  // Full output including thinking

    public init(prompt: String, documents: [String], rawResponse: String? = nil) {
        self.prompt = prompt
        self.documents = documents
        self.rawResponse = rawResponse
    }
}
