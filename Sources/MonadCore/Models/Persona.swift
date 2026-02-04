import Foundation

public struct Persona: Codable, Sendable, Identifiable {
    public let id: String  // The filename, e.g. "Default.md"
    public let content: String  // The prompt content

    public init(id: String, content: String) {
        self.id = id
        self.content = content
    }
}
