import Foundation

/// Represents a document chunk used as context for a message
public struct DocumentContext: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let content: String
    public let uri: String
    public let score: Double?
    public let metadata: [String: String]?

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        uri: String,
        score: Double? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.uri = uri
        self.score = score
        self.metadata = metadata
    }
}
