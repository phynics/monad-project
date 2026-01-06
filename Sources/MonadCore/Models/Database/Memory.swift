import Foundation
import GRDB

/// Searchable memory item for storing knowledge
public struct Memory: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: String  // JSON array stored as string
    public var metadata: String  // JSON object stored as string
    public var embedding: String // JSON array of Doubles stored as string (simulating vector storage)

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        metadata: [String: String] = [:],
        embedding: [Double] = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        
        if let data = try? JSONEncoder().encode(tags), let str = String(data: data, encoding: .utf8) {
            self.tags = str
        } else {
            self.tags = "[]"
        }
        
        if let data = try? JSONEncoder().encode(metadata), let str = String(data: data, encoding: .utf8) {
            self.metadata = str
        } else {
            self.metadata = "{}"
        }
        
        if let data = try? JSONEncoder().encode(embedding), let str = String(data: data, encoding: .utf8) {
            self.embedding = str
        } else {
            self.embedding = "[]"
        }
    }

    public var tagArray: [String] {
        guard let data = tags.data(using: .utf8),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }
    
    public var embeddingVector: [Double] {
        guard let data = embedding.data(using: .utf8),
              let vector = try? JSONDecoder().decode([Double].self, from: data)
        else {
            return []
        }
        return vector
    }

    public var metadataDict: [String: String] {
        guard let data = metadata.data(using: .utf8),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return dict
    }
}

/// Result of a semantic search including the memory and its similarity score
public struct SemanticSearchResult: Sendable, Equatable {
    public let memory: Memory
    public let similarity: Double?
    
    public init(memory: Memory, similarity: Double? = nil) {
        self.memory = memory
        self.similarity = similarity
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
