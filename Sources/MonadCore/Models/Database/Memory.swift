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

    // Non-persisted related memories (graph edges)
    public var relatedMemories: [Memory] = []

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
    
    // MARK: - FetchableRecord
    
    public init(row: Row) throws {
        // Handle ID decoding with fallback for non-hyphenated UUID strings
        if let uuid = row["id"] as? UUID {
            self.id = uuid
        } else if let uuidString = row["id"] as? String {
            if let uuid = UUID(uuidString: uuidString) {
                self.id = uuid
            } else {
                // Try inserting hyphens for raw hex string (8-4-4-4-12)
                let pattern = "([0-9a-fA-F]{8})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{12})"
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(uuidString.startIndex..., in: uuidString)
                if let match = regex.firstMatch(in: uuidString, range: range) {
                    let nsString = uuidString as NSString
                    let formatted = "\(nsString.substring(with: match.range(at: 1)))-\(nsString.substring(with: match.range(at: 2)))-\(nsString.substring(with: match.range(at: 3)))-\(nsString.substring(with: match.range(at: 4)))-\(nsString.substring(with: match.range(at: 5)))"
                    if let uuid = UUID(uuidString: formatted) {
                        self.id = uuid
                    } else {
                        throw PersistenceError.invalidUUIDFormat(uuidString)
                    }
                } else {
                    throw PersistenceError.invalidUUIDFormat(uuidString)
                }
            }
        } else {
            // Try standard decoding which handles data blobs
            self.id = row["id"]
        }
        
        self.title = row["title"]
        self.content = row["content"]
        self.createdAt = row["createdAt"]
        self.updatedAt = row["updatedAt"]
        self.tags = row["tags"]
        self.metadata = row["metadata"]
        self.embedding = row["embedding"]
    }

    // MARK: - PersistableRecord

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["title"] = title
        container["content"] = content
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
        container["tags"] = tags
        container["metadata"] = metadata
        container["embedding"] = embedding
        // relatedMemories are excluded from persistence
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.tags = try container.decode(String.self, forKey: .tags)
        self.metadata = try container.decode(String.self, forKey: .metadata)
        self.embedding = try container.decode(String.self, forKey: .embedding)
        self.relatedMemories = try container.decodeIfPresent([Memory].self, forKey: .relatedMemories) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, createdAt, updatedAt, tags, metadata, embedding, relatedMemories
    }
}

public enum PersistenceError: LocalizedError {
    case invalidUUIDFormat(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidUUIDFormat(let value):
            return "Invalid UUID format: \(value)"
        }
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

        // ID and Title
        parts.append("ID: \(id.uuidString)")
        parts.append("Title: \(title)")

        // Tags (if present)
        let tags = tagArray
        if !tags.isEmpty {
            parts.append("Tags: \(tags.joined(separator: ", "))")
        }

        // Content
        parts.append("Content:")
        parts.append(content)

        // Related Memories
        if !relatedMemories.isEmpty {
            parts.append("\nRelated Memories:")
            for related in relatedMemories {
                parts.append("- \(related.title) (ID: \(related.id.uuidString))")
            }
        }

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
