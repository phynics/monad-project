import Foundation
import GRDB

/// Searchable memory item for storing knowledge
public struct Memory: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: String  // JSON array stored as string
    public var metadata: String  // JSON object stored as string

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = (try? JSONEncoder().encode(tags).base64EncodedString()) ?? ""
        self.metadata = (try? JSONEncoder().encode(metadata).base64EncodedString()) ?? ""
    }

    public var tagArray: [String] {
        guard let data = Data(base64Encoded: tags),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }

    public var metadataDict: [String: String] {
        guard let data = Data(base64Encoded: metadata),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return dict
    }
}

// MARK: - Prompt Formatting

extension Memory: PromptFormattable {
    /// Formatted content for inclusion in LLM prompt
    public var promptString: String {
        var parts: [String] = []

        // Title
        parts.append("**\(title)**")

        // Tags (if present)
        let tags = tagArray
        if !tags.isEmpty {
            parts.append("_Tags: \(tags.joined(separator: ", "))_")
        }

        // Content
        parts.append(content)

        return parts.joined(separator: "\n")
    }
}

extension Array where Element == Memory {
    /// Format multiple memories for prompt inclusion
    public var promptContent: String {
        guard !isEmpty else { return "" }

        return """
            # Memories

            \(map { $0.promptString }.joined(separator: "\n\n"))
            """
    }
}
